#!/bin/bash
# 设置 syn-flood-detect.sh 的定时任务
# 每半小时运行一次

SCRIPT_PATH="/usr/local/bin/syn-flood-detect.sh"
CRON_JOB="0,30 * * * * $SCRIPT_PATH >> /var/log/syn_flood_cron.log 2>&1"

# 检查脚本是否存在
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "错误: $SCRIPT_PATH 不存在"
    echo "请先将 syn-flood-detect.sh 复制到 $SCRIPT_PATH"
    exit 1
fi

# 确保脚本有执行权限
chmod +x "$SCRIPT_PATH"

# 检查是否已存在相同的定时任务
if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    echo "定时任务已存在，正在更新..."
    # 删除旧的定时任务
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
fi

# 添加新的定时任务
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "✓ 定时任务已设置成功"
echo "任务详情: 每半小时运行一次 (每小时的 0 分和 30 分)"
echo "脚本路径: $SCRIPT_PATH"
echo "日志路径: /var/log/syn_flood_cron.log"
echo ""
echo "当前的 crontab 配置:"
crontab -l
