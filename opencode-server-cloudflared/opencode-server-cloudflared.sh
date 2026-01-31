#!/bin/bash

set -euo pipefail

OPENCODE_DIR="$HOME/.opencode"
OPENCODE_PID_FILE="$OPENCODE_DIR/opencode.pid"
CLOUDFLARED_PID_FILE="$OPENCODE_DIR/cloudflared.pid"
OPENCODE_LOG_FILE="$OPENCODE_DIR/opencode.log"
CLOUDFLARED_LOG_FILE="$OPENCODE_DIR/cloudflared.log"
SCRIPT_VERSION="1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Rotate logs to avoid unlimited growth.
# Keeps up to 5 historical files: <log>.1 ... <log>.5 (oldest dropped)
rotate_log() {
    local file="$1"
    local max_size_bytes="${2:-5242880}"  # default 5MB

    [ -f "$file" ] || return 0

    local size=""
    if command -v stat >/dev/null 2>&1; then
        size=$(stat -c%s "$file" 2>/dev/null || true)
    fi
    if [ -z "$size" ]; then
        size=$(wc -c < "$file" 2>/dev/null || echo 0)
    fi

    case "$size" in
        ''|*[!0-9]*) return 0 ;;
    esac

    if [ "$size" -lt "$max_size_bytes" ]; then
        return 0
    fi

    rm -f "${file}.5" 2>/dev/null || true
    for i in 4 3 2 1; do
        if [ -f "${file}.${i}" ]; then
            mv -f "${file}.${i}" "${file}.$((i+1))" 2>/dev/null || true
        fi
    done
    mv -f "$file" "${file}.1" 2>/dev/null || true
    : > "$file" 2>/dev/null || true
}


print_help() {
    # Resolve a stable script invocation path for display
    local script_path
    script_path=$(readlink -f "$0" 2>/dev/null)
    if [ -z "$script_path" ]; then
        script_path="$0"
    fi

    echo "========================================"
    echo "    OpenCode + Cloudflared 安装脚本    "
    echo "           Version $SCRIPT_VERSION            "
    echo "========================================"
    echo ""
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install                   安装并启动服务"
    echo "  interactive               交互式部署（输入端口/用户名/密码/Token）"
    echo "  status                    查看服务状态"
    echo "  stop                      停止服务"
    echo "  restart                   重启服务"
    echo "  --help, -h                显示帮助信息"
    echo ""
    echo "Options:"
    echo "  -p, --port <port>         OpenCode 服务端口 (默认: 56780)"
    echo "  -u, --user <username>     登录用户名 (默认: opencode)"
    echo "  -P, --password <password> 登录密码 (可选)"
    echo "  -t, --token <token>       Cloudflare Tunnel 密钥"
    echo ""
    echo "Examples:"
    echo "  ${script_path} install -t eyJh..."
    echo "  ${script_path} install -P YourPassword123 -t eyJh..."
    echo "  ${script_path} install -p 8080 -u admin -P YourPassword123 -t eyJh..."
    echo ""
    echo "Repository: https://github.com/anomalyco/opencode"
    echo ""
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        log_warn "建议不要使用 root 用户运行此脚本"
    fi
}

check_dependencies() {
    log_info "检查系统依赖..."

    # Detect package manager (apt/yum) for broad compatibility
    if command -v apt-get >/dev/null 2>&1; then
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update -qq"
    elif command -v yum >/dev/null 2>&1; then
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum makecache -q"
    else
        log_error "无法检测到受支持的包管理器（apt-get / yum）。请在 Debian/Ubuntu/RHEL 及其派生发行版上运行。"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_info "安装 curl..."
        $PKG_UPDATE
        $PKG_INSTALL curl
    fi

    if ! command -v wget >/dev/null 2>&1; then
        log_info "安装 wget..."
        $PKG_UPDATE
        $PKG_INSTALL wget
    fi

    log_success "依赖检查完成"
}

install_opencode() {
    mkdir -p "$OPENCODE_DIR" 2>/dev/null || true
    log_info "安装 OpenCode..."

    # Ensure PATH covers typical install locations for non-interactive shells
    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    # If already available, skip install
    if [ -n "$(find_opencode_bin)" ]; then
        log_success "OpenCode 已安装"
        return 0
    fi

    # Run official installer
    curl -fsSL https://opencode.ai/install | bash 2>&1 | tee -a "$OPENCODE_LOG_FILE"

    # Re-check after install
    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    local bin_path
    bin_path="$(find_opencode_bin)"
    if [ -n "$bin_path" ]; then
        log_success "OpenCode 安装成功（$bin_path）"
        return 0
    fi

    log_error "OpenCode 安装失败：未找到可执行文件（可能是 PATH 未生效或安装目录不同）"
    log_info "你可以手动验证：ls -la $HOME/.local/bin/opencode $HOME/.opencode/bin/opencode 2>/dev/null"
    log_info "或手动指定安装目录：OPENCODE_INSTALL_DIR=/usr/local/bin curl -fsSL https://opencode.ai/install | bash"
    return 1
}


download_cloudflared() {
    log_info "下载 Cloudflared..."

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        armv7l)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac

    mkdir -p "$OPENCODE_DIR"

    if [ -f "$OPENCODE_DIR/cloudflared" ]; then
        log_info "Cloudflared 已存在，跳过下载"
    else
        wget -q -O "$OPENCODE_DIR/cloudflared" "$CLOUDFLARED_URL"
        chmod +x "$OPENCODE_DIR/cloudflared"
    fi

    log_success "Cloudflared 准备就绪"
}

find_opencode_bin() {
    if command -v opencode &>/dev/null; then
        echo "opencode"
        return 0
    fi

    # Common install locations (installer may use XDG or fallback dirs)
    local candidates=(
        "$HOME/.local/bin/opencode"
        "$HOME/.opencode/bin/opencode"
        "$HOME/bin/opencode"
        "/usr/local/bin/opencode"
        "/usr/bin/opencode"
    )

    for f in "${candidates[@]}"; do
        if [ -x "$f" ]; then
            echo "$f"
            return 0
        fi
    done

    echo ""
}


start_services() {
    OPENCODE_PORT="${1:-56780}"
    OPENCODE_USER="${2:-opencode}"
    OPENCODE_PASSWORD="$3"
    CLOUDFLARED_TOKEN="$4"


    # Ensure we clean up partially-started services on failure
    _cleanup_on_error() {
        local rc=$?
        log_error "安装/启动过程中发生错误，正在回滚（停止已启动的进程）..."
        stop_services || true
        exit $rc
    }
    trap _cleanup_on_error ERR INT TERM

    # 端口占用检测：若端口已被占用，直接退出安装流程并给出友好提示
    port_in_use=0
    if command -v ss >/dev/null 2>&1; then
        if ss -ltnp 2>/dev/null | grep -qE ":${OPENCODE_PORT}[[:space:]]"; then
            port_in_use=1
        fi
    fi
    if [ "$port_in_use" -eq 0 ] && command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -E ":${OPENCODE_PORT}[[:space:]]"; then
            port_in_use=1
        fi
    fi
    if [ "$port_in_use" -eq 1 ]; then
        log_error "端口 ${OPENCODE_PORT} 已被占用，请更换端口再试（使用 -p 指定端口）。"
        exit 1
    fi

    if [ -z "$CLOUDFLARED_TOKEN" ]; then
        log_error "必须指定 Cloudflare Tunnel 密钥 (-t 或 --token)"
        exit 1
    fi

    log_info "开始安装和启动服务..."
    echo ""

    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

    if [ -n "$OPENCODE_USER" ]; then
        export OPENCODE_SERVER_USERNAME="$OPENCODE_USER"
    fi

    if [ -n "$OPENCODE_PASSWORD" ]; then
        export OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD"
    fi

    check_root
    check_dependencies
    install_opencode
    download_cloudflared

    OPENCODE_BIN=$(find_opencode_bin)

    if [ -z "$OPENCODE_BIN" ]; then
        log_error "未找到 OpenCode 可执行文件"
        exit 1
    fi
    rotate_log "$OPENCODE_LOG_FILE"
    rotate_log "$CLOUDFLARED_LOG_FILE"


    log_info "启动 OpenCode 服务 (端口: $OPENCODE_PORT)..."

    if [ -f "$OPENCODE_PID_FILE" ]; then
        OLD_PID=$(cat "$OPENCODE_PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    nohup "$OPENCODE_BIN" serve --port "$OPENCODE_PORT" >> "$OPENCODE_LOG_FILE" 2>&1 &
    OPENCODE_PID=$!
    echo $OPENCODE_PID > "$OPENCODE_PID_FILE"

    sleep 3
    if kill -0 $OPENCODE_PID 2>/dev/null; then
        log_success "OpenCode 已启动 (PID: $OPENCODE_PID)"

    # Health check (OpenCode server)
    # Endpoint: /global/health
    log_info "执行健康检查: /global/health"
    HEALTH_URL="http://127.0.0.1:${OPENCODE_PORT}/global/health"
    AUTH_ARGS=()
    if [ -n "$OPENCODE_PASSWORD" ]; then
        AUTH_ARGS=(-u "${OPENCODE_USER}:${OPENCODE_PASSWORD}")
    fi

    HEALTH_OK=0
    if command -v curl >/dev/null 2>&1; then
        for i in 1 2 3 4 5; do
            if curl -fsS "${AUTH_ARGS[@]}" "$HEALTH_URL" >/dev/null 2>&1; then
                HEALTH_OK=1
                break
            fi
            sleep 1
        done
    fi

    if [ "$HEALTH_OK" -eq 1 ]; then
        log_success "健康检查通过"
    else
        log_warn "健康检查未通过（可能仍在启动中或认证/网络限制）。你可以稍后手动访问: $HEALTH_URL"
    fi

    else
        log_error "OpenCode 启动失败"
        log_info "查看日志: tail -f $OPENCODE_LOG_FILE"
        exit 1
    fi

    log_info "启动 Cloudflare Tunnel..."

    if [ -f "$CLOUDFLARED_PID_FILE" ]; then
        OLD_PID=$(cat "$CLOUDFLARED_PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    nohup "$OPENCODE_DIR/cloudflared" tunnel --url "http://localhost:$OPENCODE_PORT" run --token "$CLOUDFLARED_TOKEN" >> "$CLOUDFLARED_LOG_FILE" 2>&1 &
    CLOUDFLARED_PID=$!
    echo $CLOUDFLARED_PID > "$CLOUDFLARED_PID_FILE"

    sleep 3
    if kill -0 $CLOUDFLARED_PID 2>/dev/null; then
        log_success "Cloudflared 已启动 (PID: $CLOUDFLARED_PID)"
    else
        log_error "Cloudflared 启动失败"
        log_info "查看日志: tail -f $CLOUDFLARED_LOG_FILE"
        exit 1
    fi

    sleep 2

    echo ""
    echo "========================================"
    echo "         服务已成功启动!"
    echo "========================================"
    echo ""
    echo -e "${BLUE}服务信息:${NC}"
    echo "  - OpenCode 端口: $OPENCODE_PORT"
    echo "  - 登录用户名: $OPENCODE_USER"
    echo "  - 登录密码: $OPENCODE_PASSWORD"
    echo ""
    echo -e "${BLUE}日志文件:${NC}"
    echo "  - OpenCode: $OPENCODE_LOG_FILE"
    echo "  - Cloudflared: $CLOUDFLARED_LOG_FILE"
    echo ""
    echo -e "${BLUE}常用命令:${NC}"
    echo "  查看状态: bash $0 status"
    echo "  停止服务: bash $0 stop"
    echo "  重启服务: bash $0 restart"
    echo ""

    # Clear trap handlers set during start_services
    trap - ERR INT TERM

}

interactive_deploy() {
    echo "进入交互式部署模式："
    read -p "OpenCode 端口 [56780]: " OPENCODE_PORT
    OPENCODE_PORT=${OPENCODE_PORT:-56780}
    read -p "登录用户名 [opencode]: " OPENCODE_USER
    OPENCODE_USER=${OPENCODE_USER:-opencode}
    read -s -p "登录密码（留空无密码）: " OPENCODE_PASSWORD
    echo
    read -s -p "Cloudflare Tunnel 密钥 (-t): " CLOUDFLARED_TOKEN
    echo
    if [ -z "$CLOUDFLARED_TOKEN" ]; then
        log_error "必须指定 Cloudflare Tunnel 密钥 (-t)；退出"
        exit 1
    fi
    start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN"
}

stop_services() {
    log_info "停止服务..."

    STOPPED=0

    if [ -f "$OPENCODE_PID_FILE" ]; then
        OPENCODE_PID=$(cat "$OPENCODE_PID_FILE")
        if kill -0 "$OPENCODE_PID" 2>/dev/null; then
            kill "$OPENCODE_PID" 2>/dev/null || true
            sleep 1
            if kill -0 "$OPENCODE_PID" 2>/dev/null; then
                kill -9 "$OPENCODE_PID" 2>/dev/null || true
            fi
            log_success "OpenCode 已停止 (PID: $OPENCODE_PID)"
            STOPPED=1
        fi
        rm -f "$OPENCODE_PID_FILE"
    fi

    if [ -f "$CLOUDFLARED_PID_FILE" ]; then
        CLOUDFLARED_PID=$(cat "$CLOUDFLARED_PID_FILE")
        if kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
            kill "$CLOUDFLARED_PID" 2>/dev/null || true
            sleep 1
            if kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
                kill -9 "$CLOUDFLARED_PID" 2>/dev/null || true
            fi
            log_success "Cloudflared 已停止 (PID: $CLOUDFLARED_PID)"
            STOPPED=1
        fi
        rm -f "$CLOUDFLARED_PID_FILE"
    fi

    if [ $STOPPED -eq 0 ]; then
        log_warn "没有运行的服务"
    fi
}

check_status() {
    echo "========================================"
    echo "          服务状态"
    echo "========================================"
    echo ""

    OPENCODE_RUNNING=0
    CLOUDFLARED_RUNNING=0

    if [ -f "$OPENCODE_PID_FILE" ]; then
        OPENCODE_PID=$(cat "$OPENCODE_PID_FILE")
        if kill -0 "$OPENCODE_PID" 2>/dev/null; then
            echo -e "${GREEN}[运行中]${NC} OpenCode (PID: $OPENCODE_PID)"
            OPENCODE_RUNNING=1
        else
            echo -e "${RED}[已停止]${NC} OpenCode"
        fi
    else
        echo -e "${YELLOW}[未启动]${NC} OpenCode"
    fi

    if [ -f "$CLOUDFLARED_PID_FILE" ]; then
        CLOUDFLARED_PID=$(cat "$CLOUDFLARED_PID_FILE")
        if kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
            echo -e "${GREEN}[运行中]${NC} Cloudflared (PID: $CLOUDFLARED_PID)"
            CLOUDFLARED_RUNNING=1
        else
            echo -e "${RED}[已停止]${NC} Cloudflared"
        fi
    else
        echo -e "${YELLOW}[未启动]${NC} Cloudflared"
    fi

    echo ""
    echo "========================================"
    echo "          日志预览"
    echo "========================================"

    if [ -f "$OPENCODE_LOG_FILE" ]; then
        echo ""
        echo "--- OpenCode 日志 (最后5行) ---"
        tail -5 "$OPENCODE_LOG_FILE" 2>/dev/null || true
    fi

    if [ -f "$CLOUDFLARED_LOG_FILE" ]; then
        echo ""
        echo "--- Cloudflared 日志 (最后5行) ---"
        tail -5 "$CLOUDFLARED_LOG_FILE" 2>/dev/null || true
    fi

    echo ""
    echo "========================================"
    echo "          公开访问链接"
    echo "========================================"

    if [ -f "$CLOUDFLARED_LOG_FILE" ]; then
        PUBLIC_URL=$(grep -oE 'https://[^[:space:]]+\.trycloudflare\.com' "$CLOUDFLARED_LOG_FILE" 2>/dev/null | tail -1)
        if [ -n "$PUBLIC_URL" ]; then
            echo -e "${GREEN}$PUBLIC_URL${NC}"
            echo "(提示：该链接通常来自 Quick Tunnel/临时隧道模式)"
        else
            echo "未检测到 trycloudflare 临时链接。"
            echo "(提示：你大概率使用的是 Zero Trust 控制台生成的 Token 隧道模式；公网访问地址通常是你在控制台配置的 Public Hostname/自定义域名。)"
            echo "请前往 Cloudflare Zero Trust → Networks → Tunnels 查看并绑定 Hostname。"
            echo "也可以查看 Cloudflared 日志确认连接：tail -f $CLOUDFLARED_LOG_FILE"
        fi
    else
        echo "未找到 Cloudflared 日志"
    fi

    echo ""
}

main() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        print_help
        exit 0
    fi

    if [ $# -eq 0 ]; then
        print_help
        exit 0
    fi

    COMMAND=""
    OPENCODE_PORT="56780"
    OPENCODE_USER="opencode"
    OPENCODE_PASSWORD=""
    CLOUDFLARED_TOKEN=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--port)
                OPENCODE_PORT="$2"
                shift 2
                ;;
            -u|--user)
                OPENCODE_USER="$2"
                shift 2
                ;;
            -P|--password)
                OPENCODE_PASSWORD="$2"
                shift 2
                ;;
            -t|--token)
                CLOUDFLARED_TOKEN="$2"
                shift 2
                ;;
            install|status|stop|restart|interactive)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "未知参数: $1"
                echo ""
                print_help
                exit 1
                ;;
        esac
    done

    case "$COMMAND" in
        install)
            start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN"
            ;;
        status)
            check_status
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            sleep 2
            start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN"
            ;;
        interactive)
            interactive_deploy
            ;;
        *)
            log_error "未知命令: $COMMAND"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
