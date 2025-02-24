#!/bin/sh

# OpenWrt配置项
SINGBOX_BIN="/usr/bin/sing-box"
SINGBOX_CONFIG="/etc/sing-box/config.json"
BACKUP_DIR="/etc/sing-box/backup"
GITHUB_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
LOG_FILE="/var/log/singbox-update.log"
INIT_SCRIPT="/etc/init.d/singbox"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 错误处理
error_exit() {
    log "错误: $1"
    exit 1
}

# 检查必要的命令
check_commands() {
    for cmd in curl wget; do
        if ! command -v $cmd &> /dev/null; then
            error_exit "未找到必要的命令: $cmd"
        fi
    done
}

# 创建备份
create_backup() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/$timestamp"

    mkdir -p "$backup_path" || error_exit "无法创建备份目录"
    cp "$SINGBOX_BIN" "$backup_path/" || error_exit "无法备份二进制文件"
    cp "$SINGBOX_CONFIG" "$backup_path/" || error_exit "无法备份配置文件"

    echo "$backup_path"
}

# 检查sing-box服务状态
check_service() {
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if $INIT_SCRIPT status | grep -q "running"; then
            return 0
        fi
        sleep 2
        ((retry_count++))
    done
    return 1
}

# 回滚到备份
rollback() {
    local backup_path="$1"
    log "开始回滚到备份: $backup_path"

    $INIT_SCRIPT stop
    cp "$backup_path/sing-box" "$SINGBOX_BIN"
    cp "$backup_path/config.json" "$SINGBOX_CONFIG"

    $INIT_SCRIPT start

    if check_service; then
        log "回滚成功"
        return 0
    else
        error_exit "回滚失败，请手动检查"
    fi
}

# 主更新流程
main() {
    log "开始更新流程"
    check_commands

    # 获取最新版本信息
    log "检查最新版本"
    local latest_version=$(curl -s $GITHUB_API | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
    local current_version=$($SINGBOX_BIN version | grep 'sing-box version' | awk '{print $3}')

    if [ "$latest_version" == "$current_version" ]; then
        log "已经是最新版本: $current_version"
        exit 0
    fi

    # 创建备份
    local backup_path=$(create_backup)
    log "创建备份成功: $backup_path"

    # 下载并安装新版本
    log "开始下载新版本: $latest_version"
    local download_url=$(curl -s $GITHUB_API | grep -o '"browser_download_url": ".*linux-amd64.*"' | cut -d'"' -f4)

    cd /tmp
    wget -O "sing-box.tar.gz" "$download_url" || error_exit "下载失败"
    tar -xzf "sing-box.tar.gz"

    # 停止服务
    $INIT_SCRIPT stop

    # 更新二进制文件
    cp "/tmp/sing-box-*/sing-box" "$SINGBOX_BIN"
    chmod +x "$SINGBOX_BIN"

    # 启动服务
    $INIT_SCRIPT start

    # 检查服务状态
    if check_service; then
        log "更新成功，新版本: $latest_version"
        # 清理临时文件
        rm -rf /tmp/sing-box*
    else
        log "更新后服务启动失败，开始回滚"
        rollback "$backup_path"
    fi
}

# 执行主函数
main 2>&1 | tee -a "$LOG_FILE"