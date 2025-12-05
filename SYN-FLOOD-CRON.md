# SYN Flood 检测定时任务

## 概述

`syn-flood-detect.sh` 脚本用于检测和防御 SYN Flood 攻击。该脚本已配置为每半小时自动运行一次。

## 自动部署

当运行 `init.sh` 初始化脚本时，SYN Flood 检测会自动设置：

```bash
bash init.sh
```

这将自动：
1. 安装必要的依赖（`conntrack-tools`、`whois`）
2. 将 `syn-flood-detect.sh` 复制到 `/usr/local/bin/`
3. 设置 cron 定时任务（每半小时运行一次）
4. 创建日志文件

## 手动设置

如果需要单独设置定时任务，可以使用提供的设置脚本：

```bash
bash setup-syn-flood-cron.sh
```

或者手动添加 cron 任务：

```bash
# 编辑 crontab
crontab -e

# 添加以下行（每半小时运行一次）
0,30 * * * * /usr/local/bin/syn-flood-detect.sh >> /var/log/syn_flood_cron.log 2>&1
```

## 定时任务说明

- **运行频率**: 每半小时一次（每小时的 0 分和 30 分）
- **Cron 表达式**: `0,30 * * * *`
  - `0,30` - 在第 0 分钟和第 30 分钟运行
  - `*` - 每小时
  - `*` - 每天
  - `*` - 每月
  - `*` - 每周

## 日志文件

- **检测日志**: `/var/log/syn_flood_subnet.log`
  - 记录检测到的 SYN Flood 攻击
  - 包含时间戳、网段和连接数

- **Cron 日志**: `/var/log/syn_flood_cron.log`
  - 记录定时任务的运行输出
  - 用于调试和监控

## 查看日志

```bash
# 查看检测日志
tail -f /var/log/syn_flood_subnet.log

# 查看 cron 运行日志
tail -f /var/log/syn_flood_cron.log

# 查看最近的检测记录
tail -n 20 /var/log/syn_flood_subnet.log
```

## 验证定时任务

```bash
# 查看当前的 crontab 配置
crontab -l

# 检查 cron 服务状态
systemctl status cron    # Debian/Ubuntu
systemctl status crond   # RHEL/CentOS
```

## 手动运行脚本

如果需要立即检测，可以手动运行：

```bash
/usr/local/bin/syn-flood-detect.sh
```

## 修改运行频率

如果需要修改运行频率，编辑 crontab：

```bash
crontab -e
```

常见的 cron 时间设置：

```bash
# 每 15 分钟运行一次
*/15 * * * * /usr/local/bin/syn-flood-detect.sh >> /var/log/syn_flood_cron.log 2>&1

# 每小时运行一次
0 * * * * /usr/local/bin/syn-flood-detect.sh >> /var/log/syn_flood_cron.log 2>&1

# 每天凌晨 2 点运行
0 2 * * * /usr/local/bin/syn-flood-detect.sh >> /var/log/syn_flood_cron.log 2>&1
```

## 卸载定时任务

```bash
# 编辑 crontab
crontab -e

# 删除包含 syn-flood-detect.sh 的行
# 或者使用命令删除
crontab -l | grep -v 'syn-flood-detect.sh' | crontab -
```

## 工作原理

1. **检测阶段**:
   - 使用 `conntrack` 检查处于 `SYN_SENT` 或 `SYN_RECV` 状态的连接
   - 提取可疑 IP 地址

2. **网段识别**:
   - 通过 `whois` 查询 IP 所属网段
   - 缓存已知网段以提高效率

3. **阈值判断**:
   - 统计每个网段的连接数
   - 超过阈值（默认 50）时触发防御

4. **自动防御**:
   - 将恶意网段添加到 nftables 黑名单
   - 记录到日志文件

## 配置参数

在 `syn-flood-detect.sh` 中可以调整的参数：

```bash
THRESHOLD=50              # 触发阈值（连接数）
LOG_FILE="/var/log/syn_flood_subnet.log"
CACHE_FILE="/var/run/known_subnets.txt"
```

## 故障排除

### 定时任务未运行

```bash
# 检查 cron 服务
systemctl status cron

# 启动 cron 服务
systemctl start cron
systemctl enable cron
```

### 脚本权限问题

```bash
# 确保脚本有执行权限
chmod +x /usr/local/bin/syn-flood-detect.sh
```

### 依赖缺失

```bash
# 安装必要的依赖
apt-get install conntrack whois  # Debian/Ubuntu
dnf install conntrack-tools whois # RHEL/CentOS
```

## 注意事项

1. **系统资源**: 频繁运行可能消耗系统资源，建议根据实际情况调整运行频率
2. **误报**: 阈值设置过低可能导致误报，建议根据实际流量调整
3. **日志轮转**: 建议配置 logrotate 来管理日志文件大小
4. **权限**: 脚本需要 root 权限才能修改 nftables 规则
