#!/bin/sh

#################################################
# OpenWrt sing-box 停止脚本 (强化兼容性版)
# 特性：保留原始日志架构，简化进程管理
#################################################

# 必须与启动脚本一致
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
LOG_FILE="${LOG_FILE:-/var/log/sing-box-config-stop.log}"

# 创建日志目录（原始实现保留）
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" || error_exit "无法创建日志文件"

# 使用 FIFO 实现实时双写（完全保留原始结构）
setup_logging() {
    log_pipe="/tmp/singbox_log_pipe"
    [ -p "$log_pipe" ] && rm -f "$log_pipe"
    mkfifo "$log_pipe" || error_exit "无法创建日志管道"

    tee -a "$LOG_FILE" < "$log_pipe" &
    tee_pid=$!

    trap 'cleanup_logging' EXIT
    exec 3>&1
    exec > "$log_pipe" 2>&1
}

cleanup_logging() {
    exec 1>&3 2>&3
    [ -n "$tee_pid" ] && kill $tee_pid 2>/dev/null
    [ -p "$log_pipe" ] && rm -f "$log_pipe"
}

# 初始化日志系统（无修改）
setup_logging

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

error_exit() {
    echo "$(timestamp) 错误: $1" >&2
    exit 1
}

trap 'error_exit "脚本被中断"' INT TERM

[ "$(id -u)" != "0" ] && error_exit "此脚本需要 root 权限运行"

#################################################
# 核心修改部分：简化进程管理
#################################################

# 检查并终止进程
stop_service() {
    if pgrep -x "sing-box" >/dev/null; then
        echo "$(timestamp) 正在停止 sing-box 服务..."
        killall -q sing-box && sleep 2
        if pgrep -x "sing-box" >/dev/null; then
            echo "$(timestamp) 强制终止残留进程..."
            killall -q -9 sing-box
        fi
    else
        echo "$(timestamp) 没有运行中的 sing-box 服务"
    fi
}

# 清理防火墙规则（保留关键修复）
clean_firewall() {
    echo "$(timestamp) 清理网络规则..."

    # IPv4清理
    iptables -t mangle -D PREROUTING -j TPROXY_RULE 2>/dev/null
    iptables -t mangle -F TPROXY_RULE 2>/dev/null
    iptables -t mangle -X TPROXY_RULE 2>/dev/null
    iptables -t mangle -D OUTPUT -j OUTPUT_RULE 2>/dev/null
    iptables -t mangle -F OUTPUT_RULE 2>/dev/null
    iptables -t mangle -X OUTPUT_RULE 2>/dev/null

    # IPv6清理（关键修复点）
    ip6tables -t mangle -D PREROUTING -j TPROXY_RULE 2>/dev/null
    ip6tables -t mangle -F TPROXY_RULE 2>/dev/null
    ip6tables -t mangle -X TPROXY_RULE 2>/dev/null
}

# 清理路由策略
clean_routing() {
    echo "$(timestamp) 清理路由表..."
    ip route flush table $PROXY_ROUTE_TABLE 2>/dev/null
    ip rule del fwmark $PROXY_FWMARK 2>/dev/null
    ip -6 route flush table $PROXY_ROUTE_TABLE 2>/dev/null
    ip -6 rule del fwmark $PROXY_FWMARK 2>/dev/null
}

# 清理残留文件
clean_files() {
    echo "$(timestamp) 删除临时文件..."
    rm -f /etc/sing-box/{singbox.nft,cache.db} 2>/dev/null
    rm -f /tmp/singbox_log_pipe 2>/dev/null
}

#################################################
# 主执行流程
#################################################
stop_service
clean_firewall
clean_routing
clean_files

echo "$(timestamp) 服务停止并清理完成"
cleanup_logging
