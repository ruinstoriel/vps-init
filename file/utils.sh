#!/bin/bash

# ============================================
# Utility Functions
# ============================================

# Print section header
print_section() {
    echo ""
    echo "==================================================="
    echo "$1"
    echo "==================================================="
}

# Print step message
print_step() {
    echo ""
    echo ">>> $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Error: Please run as root"
        exit 1
    fi
}

# Validate public key
validate_public_key() {
    if [ -z "$PUB_KEY" ]; then
        echo "Error: No public key provided."
        echo "Usage: $0 \"ssh-rsa ...\""
        exit 1
    fi
}

# Wait for package manager lock to be released
wait_for_lock() {
    # Only relevant for apt-get (dpkg)
    if [ "$PM" != "apt-get" ]; then
        return
    fi
    
    local i=0
    local max_wait=300 # 5 minutes
    local locked=false
    
    while true; do
        locked=false
        
        # Check using fuser if available (most reliable for file locks)
        if command -v fuser >/dev/null 2>&1; then
            if fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
               fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
               fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
                locked=true
            fi
        # Fallback to checking process names if fuser is missing
        elif pgrep -f "apt|apt-get|dpkg|unattended-upgr" >/dev/null 2>&1; then
             # Simple check for running processes
             if ps -A | grep -E 'apt|dpkg' | grep -v "grep" > /dev/null 2>&1; then
                locked=true
             fi
        fi
        
        if [ "$locked" = "false" ]; then
            if [ $i -gt 0 ]; then
                echo "Lock released. Resuming."
            fi
            break
        fi
        
        if [ $i -eq 0 ]; then
            echo "Waiting for package manager lock to be released..."
        fi
        
        sleep 5
        i=$((i + 5))
        
        if [ $i -ge $max_wait ]; then
            echo "⚠ Warning: Waited too long ($max_wait s) for lock. Proceeding anyway..."
            break
        fi
    done
}

# Detect and set package manager variables
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        PM="apt-get"
        PM_INSTALL="install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
        PM_REMOVE="remove -y --purge"
        PM_UPDATE="update"
        NFT_CONF="/etc/nftables.conf"
    elif command -v dnf &> /dev/null; then
        PM="dnf"
        PM_INSTALL="install -y"
        PM_REMOVE="remove -y"
        PM_UPDATE="makecache"
        NFT_CONF="/etc/sysconfig/nftables.conf"
        mkdir -p /etc/sysconfig
    elif command -v yum &> /dev/null; then
        PM="yum"
        PM_INSTALL="install -y"
        PM_REMOVE="remove -y"
        PM_UPDATE="makecache"
        NFT_CONF="/etc/sysconfig/nftables.conf"
        mkdir -p /etc/sysconfig
    else
        echo "Error: Unsupported package manager. Cannot install nftables."
        exit 1
    fi
    
    echo "Detected package manager: $PM"
}

# Execute file function
execute_if_exists() {
    local file="$1"
    local func_name="$2"
    shift 2  # 移除前两个参数，剩余的是函数参数
    
    # 检查文件
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # 导入文件（在子shell中避免污染当前环境）
    (
        source "$file" 2>/dev/null || return 1
        
        # 检查函数是否存在
        if declare -f "$func_name" > /dev/null 2>&1; then
            # 执行函数并传递剩余参数
            "$func_name" $@
            return $?
        else
            return 2
        fi
    )
}

# Detect system architecture
get_system_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm7"
            ;;
        s390x)
            echo "s390x"
            ;;
        *)
            return 1
            ;;
    esac
}
