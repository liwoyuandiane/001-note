#!/bin/bash

# 确保 HF CLI 在 PATH 中
export PATH="$HOME/.local/bin:$PATH"

# 从 Space Secrets 设置 HF Token
export HF_TOKEN="${HF_TOKEN}"

# 变量
SPACE_ID="${HF_SPACE}"
BUCKET="hf://buckets/${SPACE_ID}/home"
SOURCE='/home'

# 持久化日志目录
mkdir -p /home/.opencode/logs
LOG_DIR="/home/.opencode/logs"
OPENCODE_LOG_FILE="${LOG_DIR}/opencode.log"

# 启动日志文件
LOG_DATE=$(date +%Y-%m-%d)
STARTUP_LOG_FILE="/tmp/entrypoint-${LOG_DATE}.log"

# 日志函数：同时输出到终端和文件
log() {
    echo "$@" | tee -a "$STARTUP_LOG_FILE"
}

# 配置 Git
git config --global user.email 'badal@example.com'
git config --global user.name 'Badal'

log "=== [STEP -1] 创建 Bucket ==="
if hf buckets create "$SPACE_ID" 2>/dev/null; then
    log "=== [STEP -1] Bucket 已创建 ==="
else
    log "=== [STEP -1] Bucket 已存在 ==="
fi

# 设置 OpenCode 路径
OP_PATH=$(find / -name opencode -type f -printf '%h' -quit 2>/dev/null)
export PATH="$OP_PATH:$PATH"

log "=== [STEP 0] 从 Bucket 恢复数据 ==="
if hf sync "$BUCKET" "$SOURCE" -q 2>/dev/null; then
    log "=== [STEP 0] 恢复完成 ==="
else
    log "=== [STEP 0] 恢复跳过 ==="
fi

# 自动创建 /home/user 目录
if [ ! -d "/home/user" ]; then
    log "=== 创建 /home/user 文件夹 ==="
    mkdir -p /home/user
fi

# ============================================
# STEP 1: 启动 OpenCode（带 RAM 监控）
# ============================================

RAM_LIMIT_KB=$((14 * 1024 * 1024))

start_opencode() {
    log "=== [STEP 1] 启动 OpenCode ==="
    export OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}
    export OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
    opencode serve --port 7860 --hostname 0.0.0.0 > "$OPENCODE_LOG_FILE" 2>&1 &
    OPENCODE_PID=$!
    log "=== [STEP 1] OpenCode 已启动（PID: $OPENCODE_PID）==="
}

ram_watchdog() {
    while true; do
        if [ -n "$OPENCODE_PID" ] && kill -0 "$OPENCODE_PID" 2>/dev/null; then
            USED_KB=$(ps --no-headers -o rss --ppid "$OPENCODE_PID" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            SELF_KB=$(ps --no-headers -o rss -p "$OPENCODE_PID" 2>/dev/null | awk '{print $1+0}')
            TOTAL_KB=$((USED_KB + SELF_KB))

            if [ "$TOTAL_KB" -ge "$RAM_LIMIT_KB" ]; then
                log "=== [RAM] 内存超限！杀死 OpenCode（${TOTAL_KB}KB >= ${RAM_LIMIT_KB}KB）==="
                kill -9 "$OPENCODE_PID" 2>/dev/null
                sleep 3
                log '=== [RAM] 重启 OpenCode... ==='
                start_opencode
            fi
        else
            log '=== [RAM] OpenCode 未运行！重启... ==='
            start_opencode
        fi
    done
}

start_opencode
sleep 10

# 在后台运行 RAM 监控
ram_watchdog &

log "=== [STEP 2] 启动智能同步（inotify + 30秒防抖）==="

do_sync() {
    # 同步文件到 bucket（添加 .local 排除保持与 inotifywait 一致）
    hf sync "$SOURCE" "$BUCKET" --delete --ignore-sizes -q \
        --exclude "*.mdb,*.log,*/.cache/*,*/.npm/*,.check_for_update_done,rg,*/.local/*" \
        2>/dev/null || true
    
    # 上传 OpenCode 日志到 bucket
    LOG_DATE=$(date +%Y-%m-%d)
    LOG_NAME="opencode-${LOG_DATE}.log"
    hf cp "$OPENCODE_LOG_FILE" "hf://buckets/${SPACE_ID}/log/${LOG_NAME}" -q 2>/dev/null || true
    
    # 上传 entrypoint 启动日志（只上传一次）
    if [ -f "$STARTUP_LOG_FILE" ] && [ ! -f "${LOG_DIR}/entrypoint-uploaded" ]; then
        hf cp "$STARTUP_LOG_FILE" "hf://buckets/${SPACE_ID}/log/entrypoint-${LOG_DATE}.log" -q 2>/dev/null || true
        touch "${LOG_DIR}/entrypoint-uploaded"
    fi
    
    # 清理 1 个月前的旧日志
    OLD_DATE=$(date -d "30 days ago" +%Y-%m-%d)
    hf rm "hf://buckets/${SPACE_ID}/log/opencode-${OLD_DATE}.log" -q 2>/dev/null || true
    hf rm "hf://buckets/${SPACE_ID}/log/entrypoint-${OLD_DATE}.log" -q 2>/dev/null || true
}

LAST_SYNC=0

while true; do
    # 检查 OpenCode 是否仍在运行
    if ! pgrep -f 'opencode' > /dev/null; then
        log '严重错误：OpenCode 进程已退出！容器退出...'
        exit 1
    fi

    # 等待文件变更（排除 .mdb, .log, .cache, .npm, .local 等）
    inotifywait -r -e modify,create,delete,move,attrib \
        --exclude '(\.mdb$|\.log$|/\.cache/|/\.npm/|_check_for_update_done$|.*/rg$|/\.local/)' \
        -q "$SOURCE"

    # 防抖：30 秒后才执行同步
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_SYNC))

    if [ "$DIFF" -ge 30 ]; then
        do_sync
        LAST_SYNC=$(date +%s)
    fi
done