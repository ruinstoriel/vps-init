# KCPtun SSH 加速使用指南

## 概述

KCPtun 是一个基于 KCP 协议的安全隧道，可以显著提升 SSH 连接速度，特别适合：
- 跨国网络连接
- 高延迟网络环境
- 丢包率较高的网络

## 服务器端配置

服务器端已通过 `init.sh` 自动配置完成，包括：

### 1. 自动安装
- 下载并安装 KCPtun server
- 安装路径：`/usr/local/bin/kcptun-server`

### 2. Systemd 服务
- 服务名称：`kcptun.service`
- 自动启动：已启用
- 配置文件：`/etc/systemd/system/kcptun.service`

### 3. 防火墙配置
- 自动添加 UDP 端口到 nftables
- 默认端口：SSH_PORT + 1 (例如：SSH 2200，则 KCPtun 2201)

### 4. 服务器端参数
```bash
-t "127.0.0.1:2200"      # 目标 SSH 端口
-l ":2201"               # KCPtun 监听端口 (UDP)
-mode fast3              # 加速模式
-nocomp                  # 禁用压缩（SSH 已压缩）
-autoexpire 900          # 15分钟无流量自动过期
-sockbuf 16777217        # 套接字缓冲区
-dscp 46                 # DSCP 标记（QoS）
```

### 服务器管理命令

```bash
# 查看服务状态
systemctl status kcptun

# 启动服务
systemctl start kcptun

# 停止服务
systemctl stop kcptun

# 重启服务
systemctl restart kcptun

# 查看日志
journalctl -u kcptun -f

# 禁用 KCPtun
systemctl disable kcptun
systemctl stop kcptun
```

## 客户端配置

### 1. 下载 KCPtun 客户端

#### 方法 A: 使用官方脚本（Linux/Mac）
```bash
curl -L https://raw.githubusercontent.com/xtaci/kcptun/master/download.sh | sh
```

#### 方法 B: 手动下载
访问 [KCPtun Releases](https://github.com/xtaci/kcptun/releases)

下载对应平台的客户端：
- Linux: `kcptun-linux-amd64-*.tar.gz`
- macOS: `kcptun-darwin-amd64-*.tar.gz`
- Windows: `kcptun-windows-amd64-*.tar.gz`

### 2. 解压客户端

```bash
# Linux/Mac
tar -xzf kcptun-*.tar.gz

# Windows
# 使用 7-Zip 或其他解压工具
```

### 3. 使用提供的连接脚本

#### Linux/Mac
```bash
# 编辑配置
nano kcptun-client.sh

# 修改以下变量：
VPS_IP="YOUR_VPS_IP"          # 你的 VPS IP
KCPTUN_PORT="2201"            # KCPtun 端口
LOCAL_PORT="2200"             # 本地监听端口
KCPTUN_CLIENT="./client_linux_amd64"  # 客户端路径

# 运行脚本
chmod +x kcptun-client.sh
./kcptun-client.sh
```

#### Windows PowerShell
```powershell
# 编辑配置
notepad kcptun-client.ps1

# 修改以下变量：
$VPS_IP = "YOUR_VPS_IP"
$KCPTUN_PORT = "2201"
$LOCAL_PORT = "2200"
$KCPTUN_CLIENT = ".\client_windows_amd64.exe"

# 运行脚本
.\kcptun-client.ps1
```

### 4. 手动运行客户端

如果不使用脚本，可以直接运行：

```bash
# Linux/Mac
./client_linux_amd64 \
    -r "VPS_IP:2201" \
    -l ":2200" \
    -mode fast3 \
    -nocomp \
    -autoexpire 900 \
    -sockbuf 16777217 \
    -dscp 46

# Windows (PowerShell)
.\client_windows_amd64.exe `
    -r "VPS_IP:2201" `
    -l ":2200" `
    -mode fast3 `
    -nocomp `
    -autoexpire 900 `
    -sockbuf 16777217 `
    -dscp 46
```

## 连接 SSH

启动 KCPtun 客户端后，使用以下命令连接：

```bash
# 通过 KCPtun 连接
ssh -p 2200 root@localhost

# 或使用 SSH 配置文件
# 编辑 ~/.ssh/config
Host myvps-kcp
    HostName localhost
    Port 2200
    User root
    IdentityFile ~/.ssh/id_ed25519

# 然后直接连接
ssh myvps-kcp
```

## 性能优化

### 加速模式说明

KCPtun 提供多种模式，`fast3` 是推荐的平衡模式：

- `fast`: 快速模式（低延迟优先）
- `fast2`: 快速模式2（平衡）
- `fast3`: 快速模式3（推荐，平衡延迟和带宽）
- `normal`: 普通模式（带宽优先）

### 其他可调参数

如果需要进一步优化，可以调整以下参数：

```bash
# 更激进的加速（更高 CPU 使用）
-mode fast2

# 启用数据压缩（如果 SSH 未启用压缩）
# 移除 -nocomp 参数

# 调整 MTU（根据网络环境）
-mtu 1350

# 调整接收窗口大小
-rcvwnd 1024
-sndwnd 1024
```

## 故障排查

### 1. 客户端无法连接

```bash
# 检查服务器端 KCPtun 是否运行
ssh -p 2200 root@VPS_IP  # 先用直连确认 SSH 可用
systemctl status kcptun

# 检查防火墙端口
nft list table inet filter | grep 2201

# 检查服务器监听端口
ss -ulnp | grep 2201
```

### 2. 连接速度没有提升

- 确认网络环境确实需要 KCP 加速（高延迟/丢包）
- 尝试不同的 `-mode` 参数
- 检查 CPU 使用率（KCP 会增加 CPU 负载）

### 3. 查看详细日志

```bash
# 服务器端
journalctl -u kcptun -n 100 --no-pager

# 客户端
# 客户端会在终端直接输出日志
```

## 禁用 KCPtun

如果不需要 KCPtun，可以在 `init.sh` 中设置：

```bash
ENABLE_KCPTUN="false"
```

或手动禁用：

```bash
systemctl stop kcptun
systemctl disable kcptun
```

## 安全建议

1. **不要暴露原始 SSH 端口**：如果使用 KCPtun，可以考虑只开放 KCPtun 端口
2. **定期更新**：保持 KCPtun 版本更新
3. **监控资源**：KCPtun 会增加 CPU 和内存使用

## 参考资源

- [KCPtun GitHub](https://github.com/xtaci/kcptun)
- [KCP 协议](https://github.com/skywind3000/kcp)
