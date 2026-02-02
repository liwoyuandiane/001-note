#!/usr/bin/env bash
set -euo pipefail

# ---- 必需的环境变量 ----
if [[ -z "${TTYD_CREDENTIAL:-}" ]]; then
  echo "错误: 必须设置 TTYD_CREDENTIAL 环境变量 (格式: 用户名:密码)"
  echo "请在 Hugging Face Spaces -> Settings -> Variables and secrets 中添加"
  exit 1
fi

# ---- 可选的环境变量（带默认值） ----
HOME_DIR="${HOME:-/home/user/work}"
URL_SH="${URL_SH:-}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"

# ttyd 日志级别（bitmask）：默认 3=ERR(1)+WARN(2)，更安静。
# 如需更多日志：TTYD_DEBUG=7（ERR+WARN+NOTICE），或 15（再加 INFO）。
TTYD_DEBUG="${TTYD_DEBUG:-3}"

echo "启动 ttyd on :7860 ..."

# 注意：不要使用 -q！在 ttyd 中 -q 是 --exit-no-conn（无人连接就退出），在 Spaces 上会导致服务退出。
# -d 控制日志级别（默认 7）。

ttyd -p 7860 -c "${TTYD_CREDENTIAL}" -W -d "${TTYD_DEBUG}" bash &
TTYD_PID=$!

sleep 1
echo "ttyd 已启动 (PID: ${TTYD_PID})"

# ---- 启动 SSH 服务 ----
if command -v sshd &>/dev/null; then
  echo "启动 SSH 服务..."
  sudo mkdir -p /run/sshd
  sudo chmod 755 /run/sshd
  sudo /usr/sbin/sshd
  echo "SSH 服务已启动"
fi

# ---- 下载并运行可选脚本（后台执行） ----
run_user_scripts() {
  set +e  # 禁用严格模式，避免用户脚本失败导致容器退出
  
  if [[ -n "${URL_SH}" ]]; then
    echo "从 ${URL_SH} 下载脚本..."
    sudo mkdir -p "${HOME_DIR}"
    sudo chown -R user:user "${HOME_DIR}"
    cd "${HOME_DIR}" || return
    SCRIPT_NAME="$(basename "${URL_SH}")"
    
    if curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"; then
      chmod +x "${SCRIPT_NAME}"
      echo "执行脚本: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
      if [[ -n "${SCRIPT_ARGS}" ]]; then
        eval "bash ${SCRIPT_NAME} ${SCRIPT_ARGS}"
      else
        bash "${SCRIPT_NAME}"
      fi
    else
      echo "警告: 下载脚本失败: ${URL_SH}"
    fi
  else
    # ---- 运行 HOME_DIR 下的所有本地 .sh 脚本（如果没有 URL_SH） ----
    shopt -s nullglob
    for script in "${HOME_DIR}"/*.sh; do
      if [[ -f "${script}" ]]; then
        echo "执行脚本: ${script} ${SCRIPT_ARGS}"
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
echo "用户脚本在后台启动 (PID: ${SCRIPTS_PID})"

# ---- 设置 DNS（在用户脚本完成后立即设置） ----
echo "等待用户脚本完成..."
wait "${SCRIPTS_PID}" || true
echo "用户脚本已完成，设置 DNS..."
sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf' 2>/dev/null || echo "警告: DNS 设置失败"

# ---- 主进程：等待 ttyd ----
echo "主进程运行中 (PID: ${TTYD_PID})，按 Ctrl+C 可退出"
wait "${TTYD_PID}"
TTYD_EXIT_CODE=$?
echo "ttyd 已退出，退出码: ${TTYD_EXIT_CODE}"
exit $TTYD_EXIT_CODE
