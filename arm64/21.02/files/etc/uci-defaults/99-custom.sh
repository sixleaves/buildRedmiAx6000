#!/bin/sh

# 设置 /usr/bin/*.sh 的权限为 777
chmod 777 /usr/bin/*.sh 2>/dev/null

# 设置 /usr/bin/sing-box 的权限为 777
[ -f "/usr/bin/sing-box" ] && chmod 777 /usr/bin/sing-box

# 创建 /mnt/nas 目录（若不存在）
mkdir -p /mnt/nas
# 如果必须确保挂载成功，则需检查设备是否存在
if [ -b /dev/sda2 ]; then
    mount /dev/sda2 /mnt/nas
    echo "成功挂载设备到/mnt/nas"
else
    echo "警告：/dev/sda2 设备未找到，跳过挂载" >&2  # 将警告输出到标准错误
fi

# 确保脚本返回 0（成功）
exit 0
