#!/bin/bash

export PATH="$HOME/.local/bin:$PATH"
export HF_TOKEN="${HF_TOKEN}"

# 日志级别配置（默认 warning，可选 debug/info/warning）
LOG_LEVEL="${LOG_LEVEL:-warning}"
export HF_HUB_VERBOSITY="$LOG_LEVEL"
[ "$LOG_LEVEL" = "debug" ] && export HF_DEBUG=1

# 日志级别辅助函数
is_debug()  { [ "$LOG_LEVEL" = "debug" ]; }
is_verbose() { [ "$LOG_LEVEL" = "info" ] || [ "$LOG_LEVEL" = "debug" ]; }

# 变量
SPACE_ID="${HF_SPACE}"
BUCKET="hf://buckets/${SPACE_ID}/home"
SOURCE='/home'

mkdir -p /home/.opencode/logs
LOG_DIR="/home/.opencode/logs"
OPENCODE_LOG_FILE="${LOG_DIR}/opencode.log"

LOG_DATE=$(date +%Y-%m-%d)
STARTUP_LOG_FILE="/tmp/entrypoint-${LOG_DATE}.log"

log() { echo "$@" | tee -a "$STARTUP_LOG_FILE"; }

git config --global user.email 'badal@example.com'
git config --global user.name 'Badal'

log "=== [STEP -1] 创建 Bucket ==="
hf buckets create "$SPACE_ID" 2>/dev/null && log "=== [STEP -1] Bucket 已创建 ===" || log "=== [STEP -1] Bucket 已存在 ==="

OP_PATH=$(find / -name opencode -type f -printf '%h' -quit 2>/dev/null)
export PATH="$OP_PATH:$PATH"

# ============================================
# STEP 0: 从 Bucket 恢复数据
# ============================================
log "=== [STEP 0] 从 Bucket 恢复数据 ==="
is_verbose && log "正在从 bucket 恢复文件..."

START_TIME=$(date +%s)
RETRY_COUNT=0
MAX_RETRIES=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if is_debug; then
        hf sync "$BUCKET" "$SOURCE" 2>&1 | while read -r line; do log "  $line"; done
    else
        hf sync "$BUCKET" "$SOURCE" -q 2>/dev/null
    fi
    SYNC_EXIT=$?
    
    [ $SYNC_EXIT -eq 0 ] && break
    RETRY_COUNT=$((RETRY_COUNT + 1))
    is_debug && log "DEBUG: 恢复失败，重试 ($RETRY_COUNT/$MAX_RETRIES)，退出码: $SYNC_EXIT"
    [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log "=== [STEP 0] 恢复失败（已重试 $MAX_RETRIES 次）==="
else
    FILE_COUNT=$(find /home -type f 2>/dev/null | wc -l)
    DURATION=$(($(date +%s) - START_TIME))
    log "=== [STEP 0] 恢复完成（${FILE_COUNT} 个文件，耗时 ${DURATION} 秒）==="
fi

[ ! -d "/home/user" ] && mkdir -p /home/user

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
sleep 30

# 上传初始日志到 Bucket
mkdir -p /tmp/log-upload
[ -f "$OPENCODE_LOG_FILE" ] && cp "$OPENCODE_LOG_FILE" /tmp/log-upload/opencode-${LOG_DATE}.log
[ -f "$STARTUP_LOG_FILE" ] && cp "$STARTUP_LOG_FILE" /tmp/log-upload/entrypoint-${LOG_DATE}.log

if [ -n "$(ls -A /tmp/log-upload 2>/dev/null)" ]; then
    is_verbose && log "正在上传日志到 bucket..."
    if is_debug; then
        timeout 30 hf sync /tmp/log-upload "hf://buckets/${SPACE_ID}/log" 2>&1 | while read -r line; do log "  $line"; done
    else
        timeout 30 hf sync /tmp/log-upload "hf://buckets/${SPACE_ID}/log" -q 2>/dev/null || true
    fi
    touch "${LOG_DIR}/entrypoint-uploaded"
fi
rm -rf /tmp/log-upload

ram_watchdog &

log "=== [STEP 2] 启动智能同步（inotify + 30秒防抖）==="

do_sync() {
    EXCLUDE="*.mdb,*.log,*/.cache/*,*/.npm/*,.check_for_update_done,rg,*/.local/*,*/.opencode/*"
    
    if is_debug; then
        hf sync "$SOURCE" "$BUCKET" --delete --ignore-sizes --exclude "$EXCLUDE" 2>&1 | while read -r line; do log "  $line"; done
    else
        hf sync "$SOURCE" "$BUCKET" --delete --ignore-sizes -q --exclude "$EXCLUDE" 2>/dev/null || true
    fi
    
    # 上传日志到 bucket
    LOG_DATE=$(date +%Y-%m-%d)
    mkdir -p /tmp/log-sync
    [ -f "$OPENCODE_LOG_FILE" ] && cp "$OPENCODE_LOG_FILE" /tmp/log-sync/opencode-${LOG_DATE}.log
    if [ -f "$STARTUP_LOG_FILE" ] && [ ! -f "${LOG_DIR}/entrypoint-uploaded" ]; then
        cp "$STARTUP_LOG_FILE" /tmp/log-sync/entrypoint-${LOG_DATE}.log
        touch "${LOG_DIR}/entrypoint-uploaded"
    fi
    
    [ -n "$(ls -A /tmp/log-sync 2>/dev/null)" ] && {
        is_debug && { hf sync /tmp/log-sync "hf://buckets/${SPACE_ID}/log" 2>&1 | while read -r line; do log "  $line"; done; } || hf sync /tmp/log-sync "hf://buckets/${SPACE_ID}/log" -q 2>/dev/null
    }
    rm -rf /tmp/log-sync
    
    # 清理 30 天前的旧日志
    OLD_DATE=$(date -d "30 days ago" +%Y-%m-%d)
    hf buckets rm "hf://buckets/${SPACE_ID}/log/opencode-${OLD_DATE}.log" -q 2>/dev/null || true
    hf buckets rm "hf://buckets/${SPACE_ID}/log/entrypoint-${OLD_DATE}.log" -q 2>/dev/null || true
}

LAST_SYNC=0

while true; do
    pgrep -f 'opencode' > /dev/null || { log '严重错误：OpenCode 进程已退出！容器退出...'; exit 1; }

    inotifywait -r -e modify,create,delete,move,attrib \
        --exclude '(\.mdb$|\.log$|/\.cache/|/\.npm/|/\.opencode/|_check_for_update_done$|.*/rg$|/\.local/)' \
        -q "$SOURCE"

    DIFF=$(($(date +%s) - LAST_SYNC))
    [ $DIFF -ge 30 ] && { do_sync; LAST_SYNC=$(date +%s); }
done
