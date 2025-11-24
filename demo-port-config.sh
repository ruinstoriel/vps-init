#!/bin/bash

# 演示脚本：展示 SSH 端口动态配置功能
# 此脚本仅用于演示，不会实际修改系统配置

echo "========================================"
echo "SSH 端口动态配置演示"
echo "========================================"
echo ""

# 模拟配置变量
SSH_PORT="2222"
echo "1. 在 init.sh 中设置 SSH_PORT=$SSH_PORT"
echo ""

# 显示 nftables.conf 模板
echo "2. nftables.conf 模板内容（使用占位符）："
echo "   ..."
echo "   # Allow SSH (Port {{SSH_PORT}})"
echo "   tcp dport {{SSH_PORT}} accept"
echo "   ..."
echo ""

# 模拟替换过程
echo "3. 脚本运行时执行替换："
echo "   sed -i \"s/{{SSH_PORT}}/$SSH_PORT/g\" /etc/nftables.conf"
echo ""

# 显示替换后的结果
echo "4. 替换后的 nftables.conf 内容："
echo "   ..."
echo "   # Allow SSH (Port $SSH_PORT)"
echo "   tcp dport $SSH_PORT accept"
echo "   ..."
echo ""

echo "✅ 完成！SSH 端口和防火墙规则已自动同步"
echo ""
echo "优势："
echo "  - 只需修改 init.sh 中的 SSH_PORT 变量"
echo "  - 防火墙规则自动更新，无需手动修改"
echo "  - 避免配置不一致导致的锁定问题"
