#!/usr/bin/env bash
set -euo pipefail

# ---- 时间戳函数 ----
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---- 必需的环境变量 ----
if [[ -z "${TTYD_CREDENTIAL:-}" ]]; then
  log "错误: 必须设置 TTYD_CREDENTIAL 环境变量 (格式: 用户名:密码)"
  log "请在 Hugging Face Spaces -> Settings -> Variables and secrets 中添加"
  exit 1
fi

# ---- 可选的环境变量（带默认值） ----
WORK_DIR="${WORK_DIR:-/home/user/work}"  # 脚本下载和工作目录
URL_SH="${URL_SH:-}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"
SSH_TUNNEL_TOKEN="${SSH_TUNNEL_TOKEN:-}"  # Cloudflare Tunnel 令牌

# ttyd 日志级别（bitmask）：默认 3=ERR(1)+WARN(2)，更安静。
# 如需更多日志：TTYD_DEBUG=7（ERR+WARN+NOTICE），或 15（再加 INFO）。
TTYD_DEBUG="${TTYD_DEBUG:-3}"

log "启动 ttyd on :7860 ..."

# 注意：不要使用 -q！在 ttyd 中 -q 是 --exit-no-conn（无人连接就退出），在 Spaces 上会导致服务退出。
# -d 控制日志级别（默认 7）。

ttyd -p 7860 -c "${TTYD_CREDENTIAL}" -W -d "${TTYD_DEBUG}" bash &
TTYD_PID=$!

sleep 1
log "ttyd 已启动 (PID: ${TTYD_PID})"

# ---- 启动 SSH 服务 ----
if command -v sshd &>/dev/null; then
  log "启动 SSH 服务..."
  sudo mkdir -p /run/sshd
  sudo chmod 755 /run/sshd
  sudo /usr/sbin/sshd
  log "SSH 服务已启动"

  # ---- 启动 SSH 隧道（可选）----
  if [[ -n "${SSH_TUNNEL_TOKEN}" ]]; then
    log "启动 SSH 隧道..."
    sudo mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"
    
    # 下载 cloudflared（带重试）
    CLOUDFLARED_BIN="${WORK_DIR}/cloudflared"
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64) CLOUDFLARED_FILE="cloudflared-linux-amd64" ;;
      aarch64) CLOUDFLARED_FILE="cloudflared-linux-arm64" ;;
      armv7l) CLOUDFLARED_FILE="cloudflared-linux-arm" ;;
      *) log "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    if [[ ! -f "${CLOUDFLARED_BIN}" ]]; then
      RETRY_COUNT=0
      MAX_RETRIES=3
      while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if curl -fsSL -o "${CLOUDFLARED_BIN}" "https://github.com/cloudflare/cloudflared/releases/latest/download/${CLOUDFLARED_FILE}"; then
          chmod +x "${CLOUDFLARED_BIN}"
          log "cloudflared 下载成功"
          break
        else
          RETRY_COUNT=$((RETRY_COUNT + 1))
          log "cloudflared 下载失败，重试 ${RETRY_COUNT}/${MAX_RETRIES}..."
          sleep 5
        fi
      done
      
      if [[ ! -f "${CLOUDFLARED_BIN}" ]]; then
        log "错误: cloudflared 下载失败，隧道启动中止"
      fi
    fi
    
    # 启动隧道（绑定 SSH 22 端口）
    if [[ -f "${CLOUDFLARED_BIN}" ]]; then
      "${CLOUDFLARED_BIN}" tunnel --token="${SSH_TUNNEL_TOKEN}" --url ssh://localhost:22 &
      TUNNEL_PID=$!
      log "SSH 隧道已启动 (PID: ${TUNNEL_PID})"
      log "隧道令牌: ${SSH_TUNNEL_TOKEN:0:10}... (出于安全考虑只显示前10位)"
    fi
  fi
fi

# ---- 下载并运行可选脚本（后台执行） ----
run_user_scripts() {
  set +e  # 禁用严格模式，避免用户脚本失败导致容器退出
  
  if [[ -n "${URL_SH}" ]]; then
    log "从 ${URL_SH} 下载脚本..."
    sudo mkdir -p "${WORK_DIR}"
    sudo chown -R user:user "${WORK_DIR}"
    cd "${WORK_DIR}" || return
    SCRIPT_NAME="$(basename "${URL_SH}")"
    
    # 下载脚本（带重试）
    RETRY_COUNT=0
    MAX_RETRIES=3
    DOWNLOAD_SUCCESS=false
    
    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
      if curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"; then
        DOWNLOAD_SUCCESS=true
        log "脚本下载成功: ${SCRIPT_NAME}"
        break
      else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "脚本下载失败，重试 ${RETRY_COUNT}/${MAX_RETRIES}..."
        sleep 5
      fi
    done
    
    if [[ "$DOWNLOAD_SUCCESS" == "true" ]]; then
      chmod +x "${SCRIPT_NAME}"
      log "执行脚本: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
      if [[ -n "${SCRIPT_ARGS}" ]]; then
        eval "bash ${SCRIPT_NAME} ${SCRIPT_ARGS}"
      else
        bash "${SCRIPT_NAME}"
      fi
    else
      log "警告: 下载脚本失败: ${URL_SH} (已重试 ${MAX_RETRIES} 次)"
    fi
  else
    # ---- 运行 WORK_DIR 下的所有本地 .sh 脚本（如果没有 URL_SH） ----
    shopt -s nullglob
    for script in "${WORK_DIR}"/*.sh; do
      if [[ -f "${script}" ]]; then
        log "执行脚本: ${script} ${SCRIPT_ARGS}"
        if [[ -n "${SCRIPT_ARGS}" ]]; then
          eval "bash ${script} ${SCRIPT_ARGS}"
        else
          bash "${script}"
        fi
      fi
    done
    shopt -u nullglob
  fi
}

# 在后台运行用户脚本，避免阻塞主进程
run_user_scripts &
SCRIPTS_PID=$!
log "用户脚本在后台启动 (PID: ${SCRIPTS_PID})"

# ---- 设置 DNS（在用户脚本完成后立即设置） ----
log "等待用户脚本完成..."
wait "${SCRIPTS_PID}" || true

# DNS 设置（带重试）
log "用户脚本已完成，设置 DNS..."
RETRY_COUNT=0
MAX_RETRIES=3
DNS_SUCCESS=false

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  if sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf' 2>/dev/null; then
    DNS_SUCCESS=true
    log "DNS 设置成功"
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log "DNS 设置失败，重试 ${RETRY_COUNT}/${MAX_RETRIES}..."
    sleep 5
  fi
done

if [[ "$DNS_SUCCESS" != "true" ]]; then
  log "警告: DNS 设置失败 (已重试 ${MAX_RETRIES} 次)"
fi

# ---- 主进程：等待 ttyd ----
log "主进程运行中 (PID: ${TTYD_PID})，按 Ctrl+C 可退出"
wait "${TTYD_PID}"
TTYD_EXIT_CODE=$?
log "ttyd 已退出，退出码: ${TTYD_EXIT_CODE}"
exit $TTYD_EXIT_CODE
