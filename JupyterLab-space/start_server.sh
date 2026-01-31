#!/usr/bin/env bash
set -Eeuo pipefail

cleanup() {
  echo "Stopping JupyterLab..."
  if [[ -n "${JUPYTER_PID:-}" ]] && kill -0 "$JUPYTER_PID" 2>/dev/null; then
    kill "$JUPYTER_PID" 2>/dev/null || true
    wait "$JUPYTER_PID" 2>/dev/null || true
  fi
  echo "Stopped."
  exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

JUPYTER_TOKEN="${JUPYTER_TOKEN:-$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")}"

WORK_DIR="${HOME:-/home/user/work}"
URL_SH="${URL_SH:-}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"

mkdir -p "${WORK_DIR}"

TOKEN_PREFIX="${JUPYTER_TOKEN:0:8}..."
echo "JupyterLab token: ${TOKEN_PREFIX}... (full token logged for debugging)"
echo "Work directory: ${WORK_DIR}"
echo "Starting JupyterLab on :7860 ..."

jupyter labextension disable "@jupyterlab/apputils-extension:announcements" 2>/dev/null || true

export LC_ALL=zh_CN.UTF-8
export LANG=zh_CN.UTF-8

jupyter-lab \
    --ip 0.0.0.0 \
    --port 7860 \
    --no-browser \
    --allow-root \
    --ServerApp.token="$JUPYTER_TOKEN" \
    --ServerApp.tornado_settings="{'headers': {'Content-Security-Policy': \"default-src 'self' https://huggingface.co https://*.huggingface.co; frame-ancestors https://huggingface.co https://*.huggingface.co; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';\"}}" \
    --ServerApp.cookie_options="{'SameSite': 'None', 'Secure': True}" \
    --LabApp.news_url=None \
    --LabApp.check_for_updates_class="jupyterlab.NeverCheckForUpdate" \
    --notebook-dir="${WORK_DIR}" &

JUPYTER_PID=$!

for i in {1..30}; do
  if curl -fsS "http://127.0.0.1:7860" >/dev/null 2>&1; then
    echo "JupyterLab started successfully (PID: ${JUPYTER_PID})"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: JupyterLab failed to start (timeout)"
    kill "$JUPYTER_PID" 2>/dev/null || true
    wait "$JUPYTER_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

if [[ -n "${URL_SH}" ]]; then
  echo "Downloading script from ${URL_SH}..."
  cd "${WORK_DIR}"
  SCRIPT_NAME="$(basename "${URL_SH}")"
  curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"
  chmod +x "${SCRIPT_NAME}"
  echo "Running script: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
  if [[ -n "${SCRIPT_ARGS}" ]]; then
    bash "${SCRIPT_NAME}" ${SCRIPT_ARGS}
  else
    bash "${SCRIPT_NAME}"
  fi
  cd - >/dev/null || true
fi

shopt -s nullglob
for script in "${WORK_DIR}"/*.sh; do
  if [[ -f "${script}" ]]; then
    echo "Running script: ${script} ${SCRIPT_ARGS}"
    if [[ -n "${SCRIPT_ARGS}" ]]; then
      bash "${script}" ${SCRIPT_ARGS}
    else
      bash "${script}"
    fi
  fi
done
shopt -u nullglob

wait "${JUPYTER_PID}"
