#!/bin/bash
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

JUPYTER_TOKEN="${JUPYTER_TOKEN:=huggingface}"
WORK_DIR="${HOME:-/data}"
URL_SH="${URL_SH:-}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"
JUPYTERLOB="${JUPYTERLOB:-1}"

mkdir -p "$WORK_DIR"

echo "JupyterLab token: ${JUPYTER_TOKEN}"
echo "Work directory: ${WORK_DIR}"
echo "JUPYTERLOB=${JUPYTERLOB} (0=manual, 1=auto)"

export LC_ALL=zh_CN.UTF-8
export LANG=zh_CN.UTF-8

jupyter labextension disable "@jupyterlab/apputils-extension:announcements"

start_jupyterlab() {
    jupyter-lab \
        --ip 0.0.0.0 \
        --port 7860 \
        --no-browser \
        --allow-root \
        --ServerApp.token="$JUPYTER_TOKEN" \
        --ServerApp.tornado_settings="{'headers': {'Content-Security-Policy': 'frame-ancestors *'}}" \
        --ServerApp.cookie_options="{'SameSite': 'None', 'Secure': True}" \
        --ServerApp.disable_check_xsrf=True \
        --LabApp.news_url=None \
        --LabApp.check_for_updates_class="jupyterlab.NeverCheckForUpdate" \
        --notebook-dir="$WORK_DIR" &
    
    JUPYTER_PID=$!
    
    for i in {1..30}; do
        if curl -fsS "http://127.0.0.1:7860" >/dev/null 2>&1; then
            echo "JupyterLab started successfully (PID: ${JUPYTER_PID})"
            return 0
        fi
        if [[ $i -eq 30 ]]; then
            echo "ERROR: JupyterLab failed to start (timeout)"
            kill "$JUPYTER_PID" 2>/dev/null || true
            wait "$JUPYTER_PID" 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
}

run_scripts_in_background() {
    sleep 5
    echo "Starting background scripts execution..."
    
    if [[ -n "${URL_SH}" ]]; then
        echo "Downloading script from ${URL_SH}..."
        cd "$WORK_DIR"
        SCRIPT_NAME="$(basename "${URL_SH}")"
        if curl -fsSL -o "${SCRIPT_NAME}" "${URL_SH}"; then
            chmod +x "${SCRIPT_NAME}"
            echo "Running script in background: ${SCRIPT_NAME} ${SCRIPT_ARGS}"
            if [[ -n "${SCRIPT_ARGS}" ]]; then
                bash "${SCRIPT_NAME}" ${SCRIPT_ARGS} &
            else
                bash "${SCRIPT_NAME}" &
            fi
        else
            echo "WARNING: Failed to download script from ${URL_SH}"
        fi
        cd - >/dev/null || true
    fi
    
    shopt -s nullglob
    for script in "$WORK_DIR"/*.sh; do
        if [[ -f "${script}" ]]; then
            echo "Running script in background: ${script} ${SCRIPT_ARGS}"
            if [[ -n "${SCRIPT_ARGS}" ]]; then
                bash "${script}" ${SCRIPT_ARGS} &
            else
                bash "${script}" &
            fi
        fi
    done
    shopt -u nullglob
    
    echo "Background scripts initiated"
}

start_jupyterlab_manual() {
    echo "=============================================="
    echo "JUPYTERLOB=0: JupyterLab manual start mode"
    echo "=============================================="
    echo ""
    echo "To start JupyterLab manually, run:"
    echo "  jupyter-lab \\"
    echo "      --ip 0.0.0.0 \\"
    echo "      --port 7860 \\"
    echo "      --no-browser \\"
    echo "      --allow-root \\"
    echo "      --ServerApp.token=${JUPYTER_TOKEN} \\"
    echo "      --notebook-dir=${WORK_DIR}"
    echo ""
    echo "Or use the helper script:"
    echo "  bash /home/user/app/start_jupyter.sh"
    echo ""
    echo "Container will keep running. Access at: http://localhost:7860"
    echo ""
    
    cat > /home/user/app/start_jupyter.sh << SCRIPT_EOF
#!/bin/bash
jupyter-lab \
    --ip 0.0.0.0 \
    --port 7860 \
    --no-browser \
    --allow-root \
    --ServerApp.token="${JUPYTER_TOKEN}" \
    --ServerApp.tornado_settings="{'headers': {'Content-Security-Policy': 'frame-ancestors *'}}" \
    --ServerApp.cookie_options="{'SameSite': 'None', 'Secure': True}" \
    --ServerApp.disable_check_xsrf=True \
    --LabApp.news_url=None \
    --LabApp.check_for_updates_class="jupyterlab.NeverCheckForUpdate" \
    --notebook-dir="${WORK_DIR}"
SCRIPT_EOF
    chmod +x /home/user/app/start_jupyter.sh
}

if [[ "${JUPYTERLOB}" == "1" ]]; then
    echo "Starting JupyterLab on :7860 ..."
    start_jupyterlab
    run_scripts_in_background &
    wait "${JUPYTER_PID}"
else
    start_jupyterlab_manual
    run_scripts_in_background &
    echo "Container is running. Waiting for manual JupyterLab start..."
    echo "Press Ctrl+C to stop."
    while true; do
        sleep 3600
    done
fi
