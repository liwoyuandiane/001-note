#!/bin/bash

# 设置 DNS（在容器启动后执行）
echo "nameserver 8.8.8.8" > /tmp/resolv.conf
echo "nameserver 8.8.4.4" >> /tmp/resolv.conf
cp /tmp/resolv.conf /etc/resolv.conf 2>/dev/null || true

export PATH="$HOME/.local/bin:$PATH"

# 日志级别配置（默认 warning，可选 debug/info/warning）
LOG_LEVEL="${LOG_LEVEL:-warning}"

# 创建日志目录（/home/.opencode/logs 由 bucket 挂载）
mkdir -p /home/.opencode/logs
LOG_DIR='/home/.opencode/logs'
LOG_MAX_SIZE=104857600  # 100MB

log() {
    local level="$1"
    shift
    local message="$@"
    
    # 检查日志文件大小，超过 100MB 则重命名
    if [ -f "$LOG_DIR/entrypoint.log" ]; then
        LOG_SIZE=$(wc -c < "$LOG_DIR/entrypoint.log" 2>/dev/null | awk '{print $1}')
        if [ -n "$LOG_SIZE" ] && [ "$LOG_SIZE" -gt "$LOG_MAX_SIZE" ]; then
            mv "$LOG_DIR/entrypoint.log" "$LOG_DIR/entrypoint-$(date +%Y-%m-%d).log"
        fi
    fi
    
    # 根据 LOG_LEVEL 过滤日志
    case "$LOG_LEVEL" in
        debug)
            # debug: 显示所有日志
            ;;
        info)
            # info: 只显示 info/warning/error
            [ "$level" = "debug" ] && return
            ;;
        warning)
            # warning: 只显示 warning/error
            [ "$level" = "debug" ] && return
            [ "$level" = "info" ] && return
            ;;
    esac
    
    # 额外过滤：只显示重要日志到控制台
    local is_important=false
    [ "$level" = "error" ] && is_important=true
    [ "$level" = "warning" ] && is_important=true
    
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$is_important" = true ]; then
        echo "[$TIMESTAMP] [$level] $message" | tee -a "$LOG_DIR/entrypoint.log"
    else
        echo "[$TIMESTAMP] $message" >> "$LOG_DIR/entrypoint.log"
    fi
}

OPENCODE_LOG_FILE="${LOG_DIR}/opencode.log"

# 设置 OpenCode 路径
OP_PATH=$(find / -name opencode -type f -printf '%h' -quit 2>/dev/null)
if [ -n "$OP_PATH" ]; then
    export PATH="$OP_PATH:$PATH"
fi

# ============================================
# 启动 OpenCode（带 RAM 监控）
# ============================================
RAM_LIMIT_KB=$((14 * 1024 * 1024))
RAM_CHECK_INTERVAL=30

start_opencode() {
    log info "=== 启动 OpenCode ==="
    export OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}
    export OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
    opencode serve --port 7860 --hostname 0.0.0.0 > "$OPENCODE_LOG_FILE" 2>&1 &
    OPENCODE_PID=$!
    log info "=== OpenCode 已启动（PID: $OPENCODE_PID）==="
}

ram_watchdog() {
    while true; do
        if [ -n "$OPENCODE_PID" ] && kill -0 "$OPENCODE_PID" 2>/dev/null; then
            USED_KB=$(ps --no-headers -o rss --ppid "$OPENCODE_PID" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            SELF_KB=$(ps --no-headers -o rss -p "$OPENCODE_PID" 2>/dev/null | awk '{print $1+0}')
            TOTAL_KB=$((USED_KB + SELF_KB))
            
            # debug 模式显示详细 RAM 信息
            if [ "$LOG_LEVEL" = "debug" ]; then
                USED_MB=$((USED_KB / 1024))
                SELF_MB=$((SELF_KB / 1024))
                TOTAL_MB=$((TOTAL_KB / 1024))
                RAM_PERCENT=$((TOTAL_KB * 100 / RAM_LIMIT_KB))
                log debug "RAM: ${TOTAL_MB}MB / 14336MB (${RAM_PERCENT}%)"
            fi

            if [ "$TOTAL_KB" -ge "$RAM_LIMIT_KB" ]; then
                log warning "=== [RAM] 内存超限！杀死 OpenCode（${TOTAL_KB}KB >= ${RAM_LIMIT_KB}KB）==="
                kill -9 "$OPENCODE_PID" 2>/dev/null
                sleep 3
                log warning '=== [RAM] 重启 OpenCode... ==='
                start_opencode
            fi
        else
            log warning '=== [RAM] OpenCode 未运行！重启... ==='
            start_opencode
        fi
        sleep "$RAM_CHECK_INTERVAL"
    done
}

start_opencode
ram_watchdog &

log info "=== OpenCode 运行中 ==="

# 无限循环：检查 OpenCode 是否运行
while true; do
    pgrep -f 'opencode' > /dev/null || { log error '严重错误：OpenCode 进程已退出！容器退出...'; exit 1; }
    sleep "$RAM_CHECK_INTERVAL"
done