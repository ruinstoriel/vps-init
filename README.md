# VPS 初始化脚本

一个用于快速配置和加固 VPS 服务器的自动化脚本，支持 Debian/Ubuntu 和 AlmaLinux/CentOS 系统。

## 功能特性

### 🔐 SSH 安全加固
- 自动配置 SSH 公钥认证
- 禁用密码登录（PasswordAuthentication、ChallengeResponseAuthentication、KbdInteractiveAuthentication）
- 禁用 PAM 认证
- 仅允许 root 使用密钥登录（prohibit-password）

### 🛡️ 防火墙配置
- 自动安装并配置 `nftables`
- 移除旧的防火墙工具（iptables、ufw、firewalld）
- 内置防扫描规则（防止端口扫描、SYN flood 等攻击）
- 支持 IPv4 和 IPv6

### 🌐 IPv6 支持
- 自动启用 IPv6
- 配置 IPv6 自动配置和路由器通告
- 确保 IPv6 不被系统禁用

### 🔥 默认防火墙规则
开放端口：
- **22** - SSH
- **80** - HTTP
- **443** - HTTPS (TCP + UDP for QUIC)

允许协议：
- ICMP/ICMPv6（带速率限制的 Ping）
- IPv6 邻居发现（Neighbor Discovery）
- IPv6 路由器通告（Router Advertisement）
- 路径 MTU 发现（PMTUD）

安全规则：
- 丢弃无效连接状态的数据包
- 检测并阻止常见扫描（NULL scan、XMAS scan、FIN scan）
- 阻止无效的 TCP 标志组合

## 系统要求

支持的操作系统：
- Debian 8+
- Ubuntu 16.04+
- AlmaLinux 8+
- CentOS 7+
- Fedora

## 使用方法

### 1. 准备公钥文件
将你的 SSH 公钥保存为 `id_ed25519.pub`（或其他名称，需修改脚本）：
```bash
# 示例公钥内容
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx user@host
```

### 2. 上传文件到 VPS
```bash
scp init.sh nftables.conf id_ed25519.pub root@your_vps_ip:~
```

### 3. 运行初始化脚本
```bash
ssh root@your_vps_ip
chmod +x init.sh
./init.sh
```

### 4. 验证配置
**重要**：在关闭当前 SSH 会话前，请先打开一个新的终端窗口测试 SSH 密钥登录：
```bash
ssh -i ~/.ssh/id_ed25519 root@your_vps_ip
```

确认可以正常登录后再关闭原会话，以免被锁在外面。

## 文件说明

- `init.sh` - 主初始化脚本
- `nftables.conf` - nftables 防火墙规则配置
- `id_ed25519.pub` - SSH 公钥文件（需自行准备，已在 .gitignore 中）
- `.gitignore` - Git 忽略文件配置

## 配置详情

### nftables 规则结构
```
table inet filter {
    chain prerouting (priority -150)  # 早期丢弃恶意流量
    chain input (policy drop)          # 默认拒绝所有入站
    chain forward (policy drop)        # 默认拒绝转发
    chain output (policy accept)       # 允许所有出站
}
```

### IPv6 配置
脚本会自动配置以下参数：
```
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.all.disable_ipv6 = 0
```

## 注意事项

⚠️ **警告**：
1. 运行此脚本会修改系统的 SSH 和防火墙配置
2. 确保你的公钥正确无误，否则可能无法登录
3. 建议先在测试环境或虚拟机上验证
4. 脚本会删除 iptables、ufw、firewalld 等旧防火墙工具

## 故障排除

### SSH 无法连接
1. 检查公钥是否正确添加到 `~/.ssh/authorized_keys`
2. 检查文件权限：`chmod 600 ~/.ssh/authorized_keys`
3. 查看 SSH 日志：`journalctl -u sshd -f`

### nftables 启动失败
1. 检查配置文件语法：`nft -f /etc/nftables.conf`
2. 查看服务状态：`systemctl status nftables`
3. 查看日志：`journalctl -xe`

### IPv6 不工作
1. 检查 sysctl 配置：`sysctl -a | grep ipv6`
2. 重启网络服务：`systemctl restart network`
3. 检查路由：`ip -6 route`

## 自定义配置

### 修改开放端口
编辑 `nftables.conf`，在 `chain input` 中添加规则：
```nft
tcp dport 8080 accept  # 开放 TCP 8080 端口
udp dport 53 accept    # 开放 UDP 53 端口
```

### 添加 IP 白名单
```nft
ip saddr 1.2.3.4 accept  # 允许特定 IP
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
