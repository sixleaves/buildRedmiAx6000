#!/bin/sh

#################################################
# 描述: OpenWrt sing-box TProxy模式 配置脚本
# 用途: 配置和启动 sing-box TProxy模式 代理服务 (iptables 版本)
#################################################
TPROXY_PORT=7895      # 和配置文件的端口一致
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
MAX_RETRIES=3
RETRY_DELAY=3
CONFIG_FILE="/etc/sing-box/config.json"
CONFIG_BACKUP="/etc/sing-box/config.json.backup"
LOG_FILE="${LOG_FILE:-/var/log/sing-box-config.log}"

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

# 初始化日志系统
setup_logging

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

error_exit() {
    echo "$(timestamp) 错误: $1" >&2
    exit "${2:-1}"
}

trap 'error_exit "脚本被中断"' INT TERM

# 停止 sing-box 服务
if killall sing-box 2>/dev/null; then
    echo "$(timestamp) 已停止现有 sing-box 服务"
else
    echo "$(timestamp) 没有运行中的 sing-box 服务"
fi

# 清理旧规则
clean_rules() {
    iptables -t mangle -D PREROUTING -j TPROXY_RULE 2>/dev/null
    iptables -t mangle -F TPROXY_RULE 2>/dev/null
    iptables -t mangle -X TPROXY_RULE 2>/dev/null

    ip6tables -t mangle -D PREROUTING -j TPROXY_RULE 2>/dev/null
    ip6tables -t mangle -F TPROXY_RULE 2>/dev/null
    ip6tables -t mangle -X TPROXY_RULE 2>/dev/null

    iptables -t mangle -D OUTPUT -j OUTPUT_RULE 2>/dev/null
    iptables -t mangle -F OUTPUT_RULE 2>/dev/null
    iptables -t mangle -X OUTPUT_RULE 2>/dev/null
}

check_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error_exit "$cmd 未安装，请安装后再运行此脚本"
    fi
}

check_network() {
    local test_host="223.5.5.5"
    echo "$(timestamp) 检查网络连接..."
    if ! ping -c 1 -W 3 $test_host >/dev/null 2>&1; then
        error_exit "网络连接失败，请检查网络设置"
    fi
}

check_port() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        echo "端口 $port 已被占用.强制重启"
        pgrep "sing-box" | xargs kill -9
    fi
}

backup_config() {
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    echo "$(timestamp) 已备份当前配置"
}

restore_config() {
    [ -f "$CONFIG_BACKUP" ] && cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    echo "$(timestamp) 已还原至备份配置"
}

# 主程序开始
[ "$(id -u)" != "0" ] && error_exit "此脚本需要 root 权限运行"

check_command "sing-box"
check_command "curl"
check_command "iptables"
check_command "ip"
check_command "ping"

check_network
check_port "$TPROXY_PORT"
clean_rules

# 创建自定义链
iptables -t mangle -N TPROXY_RULE
iptables -t mangle -N OUTPUT_RULE
ip6tables -t mangle -N TPROXY_RULE

# IPv4 规则配置
iptables -t mangle -A PREROUTING -j TPROXY_RULE
iptables -t mangle -A OUTPUT -j OUTPUT_RULE

# IPv6 规则配置
ip6tables -t mangle -A PREROUTING -j TPROXY_RULE

# 公共规则函数
add_tproxy_rules() {
    local ipt=$1
    # 放行 DHCP/DNS
    $ipt -t mangle -A TPROXY_RULE -p udp --dport 67:68 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -p udp --dport 53 -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $PROXY_FWMARK

    # 放行本地网络
    $ipt -t mangle -A TPROXY_RULE -d 0.0.0.0/8 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -d 127.0.0.0/8 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -d 10.0.0.0/8 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -d 172.16.0.0/12 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -d 192.168.0.0/16 -j RETURN
    $ipt -t mangle -A TPROXY_RULE -d 169.254.0.0/16 -j RETURN

    # DNAT 流量放行
    $ipt -t mangle -A TPROXY_RULE -m conntrack --ctstate DNAT -j RETURN

    # 主 TPROXY 规则
    $ipt -t mangle -A TPROXY_RULE -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $PROXY_FWMARK
    $ipt -t mangle -A TPROXY_RULE -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $PROXY_FWMARK
}

# 配置 OUTPUT 链
iptables -t mangle -A OUTPUT_RULE -m mark --mark $PROXY_FWMARK -j RETURN
iptables -t mangle -A OUTPUT_RULE -p udp --dport 53 -j MARK --set-mark $PROXY_FWMARK
iptables -t mangle -A OUTPUT_RULE -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A OUTPUT_RULE -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A OUTPUT_RULE -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A OUTPUT_RULE -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A OUTPUT_RULE -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A OUTPUT_RULE -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A OUTPUT_RULE -p tcp -j MARK --set-mark $PROXY_FWMARK
iptables -t mangle -A OUTPUT_RULE -p udp -j MARK --set-mark $PROXY_FWMARK

# 应用规则
add_tproxy_rules iptables
add_tproxy_rules ip6tables

# 路由策略配置
ip route flush table $PROXY_ROUTE_TABLE
ip rule del fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE 2>/dev/null
ip rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE
ip route add local default dev lo table $PROXY_ROUTE_TABLE

# IPv6 路由策略
ip -6 route flush table $PROXY_ROUTE_TABLE
ip -6 rule del fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE 2>/dev/null
ip -6 rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE
ip -6 route add local default dev lo table $PROXY_ROUTE_TABLE

# 启动服务
echo "$(timestamp) 启动 sing-box 服务..."
sing-box run -c "$CONFIG_FILE" >/dev/null 2>&1 &

sleep 2
if pgrep -x "sing-box" >/dev/null; then
    echo "$(timestamp) sing-box 启动成功 (TProxy模式)"
else
    error_exit "sing-box 启动失败，请检查配置"
fi

cleanup_logging