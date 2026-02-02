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

# 创建目录（带权限检查）
if ! mkdir -p "${HOME_DIR}" 2>/dev/null; then
  echo "警告: 无法创建目录 ${HOME_DIR}，尝试使用 sudo..."
  sudo mkdir -p "${HOME_DIR}" || true
fi

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
    cd "${HOME_DIR}" || return
    SCRIPT_NAME="$(basename "${URL_SH}")"
    
    if curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"; then
      chmod +x "${SCRIPT_NAME}"
      echo "执行脚本: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
      if [[ -n "${SCRIPT_ARGS}" ]]; then
        bash "${SCRIPT_NAME}" ${SCRIPT_ARGS}
      else
        bash "${SCRIPT_NAME}"
      fi
      SCRIPT_EXIT_CODE=$?
      if [[ $SCRIPT_EXIT_CODE -ne 0 ]]; then
        echo "警告: 脚本执行失败，退出码: ${SCRIPT_EXIT_CODE}"
      fi
    else
      echo "警告: 下载脚本失败: ${URL_SH}"
    fi
  else
    # ---- 运行 HOME_DIR 下的所有本地 .sh 脚本（如果没有 URL_SH） ----
    shopt -s nullglob
    local script_count=0
    for script in "${HOME_DIR}"/*.sh; do
      if [[ -f "${script}" ]]; then
        script_count=$((script_count + 1))
        echo "执行脚本: ${script} ${SCRIPT_ARGS}"
        if [[ -n "${SCRIPT_ARGS}" ]]; then
          bash "${script}" ${SCRIPT_ARGS}
        else
          bash "${script}"
        fi
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
          echo "警告: 脚本 ${script} 执行失败，退出码: ${exit_code}"
        fi
      fi
    done
    shopt -u nullglob
    
    if [[ $script_count -eq 0 ]]; then
      echo "提示: 未找到 URL_SH，且 ${HOME_DIR} 下没有 .sh 脚本文件"
    fi
  fi
}

# 在后台运行用户脚本，避免阻塞主进程
run_user_scripts &
SCRIPTS_PID=$!
echo "用户脚本在后台启动 (PID: ${SCRIPTS_PID})"

# ---- 主进程：等待 ttyd ----
# ttyd 是主进程，容器随 ttyd 生命周期管理
echo "主进程等待 ttyd (PID: ${TTYD_PID})..."
wait "${TTYD_PID}"
TTYD_EXIT_CODE=$?
echo "ttyd 已退出，退出码: ${TTYD_EXIT_CODE}"

# 可选：等待用户脚本完成
if kill -0 "$SCRIPTS_PID" 2>/dev/null; then
  echo "等待用户脚本完成..."
  wait "$SCRIPTS_PID" || true
fi

exit $TTYD_EXIT_CODE
