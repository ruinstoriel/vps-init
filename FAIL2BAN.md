# Fail2ban 集成说明

## 新增功能

VPS 初始化脚本现已集成 Fail2ban 入侵防护系统。

## 自动配置内容

### 1. 安装
- 自动安装 fail2ban 包
- 验证安装成功

### 2. 配置文件
创建以下配置文件：

**`/etc/fail2ban/jail.local`**
- 默认封禁时间：1小时
- 检测时间窗口：10分钟
- 最大重试次数：5次
- SSH 特定配置：3次失败尝试，封禁24小时
- **自动检测日志路径**：
  - Debian 12+ / 现代系统：使用 systemd journal backend
  - Debian 11- / Ubuntu：使用 `/var/log/auth.log`
  - RHEL/CentOS：使用 `/var/log/secure`

**nftables 集成**
- 使用系统自带的 `nftables-multiport` 和 `nftables-allports` actions
- 无需创建额外的 action 配置文件
- 封禁的 IP 会自动添加到 nftables 的 `inet filter` 表中

### 3. 与 nftables 集成
- 自动使用 nftables-multiport 作为封禁动作
- 封禁的 IP 会被添加到 nftables 规则中
- 无需手动管理 IP 黑名单

### 4. SSH 端口同步
- 自动读取 `init.sh` 中的 `SSH_PORT` 变量
- 配置 Fail2ban 监控正确的 SSH 端口

## 使用方法

### 查看状态
```bash
# 查看 Fail2ban 整体状态
fail2ban-client status

# 查看 SSH jail 详情
fail2ban-client status sshd

# 查看被封禁的 IP（通过 nftables）
nft list ruleset | grep fail2ban
```

### 手动操作
```bash
# 解封 IP
fail2ban-client set sshd unbanip 1.2.3.4

# 封禁 IP
fail2ban-client set sshd banip 1.2.3.4

# 重新加载配置
fail2ban-client reload
```

### 自定义配置
编辑 `/etc/fail2ban/jail.local`：
```ini
[DEFAULT]
bantime  = 2h        # 修改默认封禁时间
findtime = 20m       # 修改检测窗口
maxretry = 3         # 修改最大重试次数

[sshd]
maxretry = 5         # SSH 特定设置
bantime = 1w         # 封禁1周
```

修改后重启：
```bash
systemctl restart fail2ban
```

## 日志位置
- Fail2ban 日志：`/var/log/fail2ban.log`
- 系统日志：`journalctl -u fail2ban`
- SSH 认证日志：`/var/log/auth.log` (Debian/Ubuntu) 或 `/var/log/secure` (RHEL/CentOS)

## 注意事项
1. 确保不要封禁自己的 IP（建议添加 IP 白名单）
2. 封禁规则会在 Fail2ban 重启后清空
3. 如需永久封禁，应直接在 nftables 配置中添加规则
4. **日志路径自动检测**：脚本会自动检测系统使用的日志方式
   - Debian 12+ 等现代系统使用 systemd journal
   - 旧版系统使用传统日志文件（`/var/log/auth.log` 或 `/var/log/secure`）
5. **nftables actions**：使用系统自带的 actions，无需手动配置

## 添加 IP 白名单
编辑 `/etc/fail2ban/jail.local`，在 `[DEFAULT]` 部分添加：
```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 your.trusted.ip.address
```

## 扩展其他服务
可以在 `/etc/fail2ban/jail.local` 中添加其他服务的保护：

```ini
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
```

重启 Fail2ban 使配置生效：
```bash
systemctl restart fail2ban
```
