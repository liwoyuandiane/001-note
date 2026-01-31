#!/usr/bin/env bash
set -euo pipefail

# ---- Required env ----
if [[ -z "${TTYD_CREDENTIAL:-}" ]]; then
  echo "错误: 必须设置 TTYD_CREDENTIAL 环境变量 (格式: 用户名:密码)"
  echo "请在 Hugging Face Spaces -> Settings -> Variables and secrets 中添加"
  exit 1
fi

# ---- Optional env (with defaults) ----
HOME_DIR="${HOME:-/home/user/work}"
URL_SH="${URL_SH:-}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"

# ttyd 日志级别（bitmask）：默认 3=ERR(1)+WARN(2)，更安静。
# 如需更多日志：TTYD_DEBUG=7（ERR+WARN+NOTICE），或 15（再加 INFO）。
TTYD_DEBUG="${TTYD_DEBUG:-3}"

mkdir -p "${HOME_DIR}"

echo "启动 ttyd on :7860 ..."

# 注意：不要使用 -q！在 ttyd 中 -q 是 --exit-no-conn（无人连接就退出），在 Spaces 上会导致服务退出。
# -d 控制日志级别（默认 7）。

ttyd -p 7860 -c "${TTYD_CREDENTIAL}" -W -d "${TTYD_DEBUG}" bash &
TTYD_PID=$!

sleep 1
echo "ttyd 已启动 (PID: ${TTYD_PID})"

# ---- Download & run optional script ----
if [[ -n "${URL_SH}" ]]; then
  echo "从 ${URL_SH} 下载脚本..."
  cd "${HOME_DIR}"
  SCRIPT_NAME="$(basename "${URL_SH}")"
  curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"
  chmod +x "${SCRIPT_NAME}"
  echo "执行脚本: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
  if [[ -n "${SCRIPT_ARGS}" ]]; then
    bash "${SCRIPT_NAME}" ${SCRIPT_ARGS}
  else
    bash "${SCRIPT_NAME}"
  fi
fi

# ---- Run all local *.sh under HOME_DIR (if any) ----
shopt -s nullglob
for script in "${HOME_DIR}"/*.sh; do
  if [[ -f "${script}" ]]; then
    echo "执行脚本: ${script} ${SCRIPT_ARGS}"
    if [[ -n "${SCRIPT_ARGS}" ]]; then
      bash "${script}" ${SCRIPT_ARGS}
    else
      bash "${script}"
    fi
  fi
done
shopt -u nullglob

wait "${TTYD_PID}"
