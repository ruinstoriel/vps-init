#!/bin/bash

# 指定完整路径
CONNTRACK="/usr/sbin/conntrack"
NFT="/usr/sbin/nft"
WHOIS="/usr/bin/whois"

LOG_FILE="/var/log/syn_flood.log"
CACHE_FILE="/var/run/known_subnets.txt"
THRESHOLD=40

# 错误处理函数
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" >> "$LOG_FILE"
}
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $1" >> "$LOG_FILE"
}
# 检查关键命令
if [ ! -x "$CONNTRACK" ]; then
    log_error "conntrack not found or not executable at $CONNTRACK"
    exit 1
fi

if [ ! -x "$NFT" ]; then
    log_error "nft not found or not executable at $NFT"
    exit 1
fi

# 检查权限
if [ "$EUID" -ne 0 ]; then
    log_error "Script must run as root, current UID: $EUID"
    exit 1
fi

touch "$CACHE_FILE" "$LOG_FILE" 2>/dev/null || {
    log_error "Cannot create log files"
    exit 1
}

# 将IP范围转换为CIDR格式
convert_ip_range_to_cidr() {
    local start_ip=$1
    local end_ip=$2
    
    # 将IP转换为整数
    IFS=. read -r a b c d <<< "$start_ip"
    local start_int=$((a * 256**3 + b * 256**2 + c * 256 + d))
    
    IFS=. read -r a b c d <<< "$end_ip"
    local end_int=$((a * 256**3 + b * 256**2 + c * 256 + d))
    
    # 计算范围大小
    local range_size=$((end_int - start_int + 1))
    
    # 计算最接近的CIDR掩码
    local mask=32
    local power=1
    while [ $power -lt $range_size ] && [ $mask -gt 0 ]; do
        power=$((power * 2))
        mask=$((mask - 1))
    done
    
    # 返回CIDR格式
    echo "${start_ip}/${mask}"
}

# 检查IP是否在已知网段内
ip_in_cached_subnets() {
    local ip=$1
    local ip_int
    
    IFS=. read -r a b c d <<< "$ip"
    ip_int=$((a * 256**3 + b * 256**2 + c * 256 + d))
    
    while read -r subnet; do
        IFS=/ read -r net mask <<< "$subnet"
        IFS=. read -r a b c d <<< "$net"
        net_int=$((a * 256**3 + b * 256**2 + c * 256 + d))
        mask_int=$(( (0xFFFFFFFF << (32 - mask)) & 0xFFFFFFFF ))
        
        if [ $((ip_int & mask_int)) -eq $((net_int & mask_int)) ]; then
            log_info "IP $ip is in subnet $subnet"
            return 0
        fi
    done < "$CACHE_FILE"
    
    return 1
}

declare -A subnet_count

# 提取半开连接的源IP
get_syn_ips() {
    local result
    result=$($CONNTRACK -L 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "conntrack -L failed with exit code $exit_code: $result"
        return 1
    fi
    
    echo "$result" | \
        grep -E "SYN_SENT|SYN_RECV" | \
        awk '{for(i=1;i<=NF;i++) if($i~/^src=/) {print $i; break}}' | \
        cut -d= -f2 | \
        grep -E '^[0-9.]+$' | \
        sort -u
}

# 第一次采样
sample1=$(get_syn_ips)
if [ $? -ne 0 ]; then
    log_error "First sampling failed"
    exit 1
fi

# 等待2秒
sleep 2

# 第二次采样
sample2=$(get_syn_ips)
if [ $? -ne 0 ]; then
    log_error "Second sampling failed"
    exit 1
fi

# 只统计在两次采样中都出现的IP
suspicious_ips=$(comm -12 <(echo "$sample1") <(echo "$sample2"))

if [ -z "$suspicious_ips" ]; then
    # 没有可疑IP，正常退出
    exit 0
fi

for ip in $suspicious_ips; do
    # 跳过内网
    [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] && continue
    
    # 检查缓存
    subnet=$(ip_in_cached_subnets "$ip")
    
    if [ -z "$subnet" ]; then
        # whois查询
        whois_output=$(timeout 3 $WHOIS "$ip" 2>/dev/null)
        
        # 首先尝试获取CIDR格式
        subnet=$(echo "$whois_output" | \
            grep -iE "^(CIDR|inetnum):" | \
            head -1 | \
            awk '{print $NF}' | \
            grep -E '^[0-9.]+/[0-9]+$')
        
        # 如果没有CIDR格式，尝试获取IP范围格式
        if [ -z "$subnet" ]; then
            ip_range=$(echo "$whois_output" | \
                grep -iE "^(inetnum|NetRange):" | \
                head -1 | \
                sed -E 's/^[^:]+:\s*//' | \
                grep -E '^[0-9.]+ - [0-9.]+$')
            
            if [ -n "$ip_range" ]; then
                # 提取起始和结束IP
                start_ip=$(echo "$ip_range" | awk '{print $1}')
                end_ip=$(echo "$ip_range" | awk '{print $3}')
                
                # 转换为CIDR格式
                subnet=$(convert_ip_range_to_cidr "$start_ip" "$end_ip")
                log_info "Converted IP range $ip_range to CIDR: $subnet"
            fi
        fi
        
        if [ -z "$subnet" ]; then
            subnet=$(echo "$ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
            log_error "whois failed for $ip, using fallback: $subnet"
        fi
        
        # 加入缓存
        grep -q "^${subnet}$" "$CACHE_FILE" || echo "$subnet" >> "$CACHE_FILE"
    fi
    
    ((++subnet_count["$subnet"]))
done

# 输出到日志
for subnet in "${!subnet_count[@]}"; do
    count=${subnet_count[$subnet]}
    if [ "$count" -ge "$THRESHOLD" ]; then
        log_info "$(date '+%Y-%m-%d %H:%M:%S') SYN_FLOOD subnet=$subnet count=$count"
        
        # 尝试封禁并检查结果
        nft_output=$($NFT add element inet filter ipv4_block { "$subnet" } 2>&1)
        if [ $? -ne 0 ]; then
            log_error "nft failed to block $subnet: $nft_output"
        fi
    fi
done

exit 0