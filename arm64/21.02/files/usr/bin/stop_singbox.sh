#!/bin/sh
# 默认日志文件路径
LOG_FILE="${LOG_FILE:-/var/log/sing-box-config-stop.log}"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" || error_exit "无法创建日志文件"

# 使用 FIFO 实现实时双写
setup_logging() {
    # 创建命名管道
    log_pipe="/tmp/singbox_log_pipe"
    [ -p "$log_pipe" ] && rm -f "$log_pipe"
    mkfifo "$log_pipe" || error_exit "无法创建日志管道"

    # 启动后台写入进程
    tee -a "$LOG_FILE" < "$log_pipe" &
    tee_pid=$!

    # 设置退出清理
    trap 'cleanup_logging' EXIT

    # 重定向输出到管道
    exec 3>&1  # 备份原始 stdout
    exec > "$log_pipe" 2>&1
}

cleanup_logging() {
    # 恢复原始输出
    exec 1>&3 2>&3
    # 清理后台进程和管道
    [ -n "$tee_pid" ] && kill $tee_pid 2>/dev/null
    [ -p "$log_pipe" ] && rm -f "$log_pipe"
}

setup_logging

# 获取当前时间
timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}
# 错误处理函数
error_exit() {
    echo "$(timestamp) 错误: $1" >&2
    exit "${2:-1}"
}
# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error_exit "$cmd 未安装，请安装后再运行此脚本"
    fi
}
# 捕获中断信号以进行清理
trap 'error_exit "脚本被中断"' INT TERM
# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    error_exit "此脚本需要 root 权限运行"
fi
# 检查必要命令是否安装
check_command "sing-box"
check_command "nft"
check_command "ip"

# 停止 sing-box 服务（包括沙盒实例）
if pgrep "sing-box" > /dev/null; then
    # 先尝试正常终止
    killall sing-box
    sleep 1
    # 如果还在运行，强制终止
    if pgrep "sing-box" > /dev/null; then
        killall -9 sing-box
    fi
    echo "$(timestamp) 已停止现有 sing-box 服务"
else
    echo "$(timestamp) 没有运行中的 sing-box 服务"
fi

# 确保 ujail 实例被清理
if ps | grep -v grep | grep "ujail -n sing-box" > /dev/null; then
    pkill -f "ujail -n sing-box"
    echo "$(timestamp) 已清理 sing-box 沙盒实例"
fi

# 删除防火墙规则文件
rm -f /etc/sing-box/singbox.nft && echo "$(timestamp) 已删除防火墙规则文件"

# 删除 sing-box 表
nft delete table inet sing-box 2>/dev/null && echo "$(timestamp) 已删除 sing-box 表"

# 删除路由规则和清理路由表
ip rule del fwmark 1 table 100 2>/dev/null && echo "$(timestamp) 已删除路由规则"
ip route flush table 100 && echo "$(timestamp) 已清理路由表"

# 清理 IPv6 路由规则（如果有）
ip -6 rule del fwmark 1 table 100 2>/dev/null && echo "$(timestamp) 已删除 IPv6 路由规则"
ip -6 route flush table 100 2>/dev/null && echo "$(timestamp) 已清理 IPv6 路由表"

# 删除缓存
rm -f /etc/sing-box/cache.db && echo "$(timestamp) 已清理缓存文件"

echo "$(timestamp) 停止sing-box并清理完毕"
cleanup_logging