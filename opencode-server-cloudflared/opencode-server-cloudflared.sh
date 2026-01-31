#!/bin/bash
set -euo pipefail

OPENCODE_DIR="$HOME/.opencode"
OPENCODE_PID_FILE="$OPENCODE_DIR/opencode.pid"
CLOUDFLARED_PID_FILE="$OPENCODE_DIR/cloudflared.pid"
OPENCODE_LOG_FILE="$OPENCODE_DIR/opencode.log"
CLOUDFLARED_LOG_FILE="$OPENCODE_DIR/cloudflared.log"
PUBLIC_HOSTNAME_FILE="$OPENCODE_DIR/public_hostname"
SCRIPT_VERSION="1.0.2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

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

save_public_hostname() {
    local h="${1:-}"
    mkdir -p "$OPENCODE_DIR" 2>/dev/null || true
    if [ -n "$h" ]; then
        echo "$h" > "$PUBLIC_HOSTNAME_FILE"
    fi
}

load_public_hostname() {
    if [ -f "$PUBLIC_HOSTNAME_FILE" ]; then
        head -n 1 "$PUBLIC_HOSTNAME_FILE" 2>/dev/null || true
    fi
}

print_help() {
    local script_path
    script_path=$(readlink -f "$0" 2>/dev/null || true)
    if [ -z "${script_path:-}" ]; then
        script_path="$0"
    fi

    echo "========================================"
    echo "    OpenCode + Cloudflared 安装脚本"
    echo "    Version $SCRIPT_VERSION"
    echo "========================================"
    echo ""
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install                   安装并启动服务"
    echo "  interactive               交互式部署（输入端口/用户名/密码/Token/域名）"
    echo "  status                    查看服务状态"
    echo "  stop                      停止服务"
    echo "  restart                   重启服务"
    echo "  --help, -h                显示帮助信息"
    echo ""
    echo "Options:"
    echo "  -p, --port <port>              OpenCode 服务端口 (默认: 56780)"
    echo "  -u, --user <username>          登录用户名 (默认: opencode)"
    echo "  -P, --password <password>      登录密码 (可选)"
    echo "  -t, --token <token>            Cloudflare Tunnel 密钥 (必填)"
    echo "  -H, --public-hostname <host>   你的自定义公网域名(可选，如 app.example.com，会在 status 中显示并持久化保存)"
    echo ""
    echo "Examples:"
    echo "  ${script_path} install -t eyJh..."
    echo "  ${script_path} install -P YourPassword123 -t eyJh..."
    echo "  ${script_path} install -p 8080 -u admin -P YourPassword123 -t eyJh..."
    echo "  ${script_path} install -t eyJh... -H app.example.com"
    echo "  ${script_path} interactive"
    echo ""
    echo "Repository: https://github.com/anomalyco/opencode"
    echo ""
}

check_root() {
    if [ "${EUID:-1000}" -eq 0 ]; then
        log_warn "建议不要使用 root 用户运行此脚本"
    fi
}

check_dependencies() {
    log_info "检查系统依赖..."

    local PKG_INSTALL=""
    local PKG_UPDATE=""

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

    if command -v opencode >/dev/null 2>&1; then
        log_success "OpenCode 已安装"
        return 0
    fi

    curl -fsSL https://opencode.ai/install | bash 2>&1 | tee -a "$OPENCODE_LOG_FILE" || true
    export PATH="$HOME/.local/bin:$PATH"

    if command -v opencode >/dev/null 2>&1; then
        log_success "OpenCode 安装成功"
    else
        log_error "OpenCode 安装失败，请手动安装"
        log_info  "访问 https://opencode.ai 获取安装帮助"
        return 1
    fi
}

download_cloudflared() {
    log_info "下载 Cloudflared..."

    local ARCH
    ARCH="$(uname -m)"

    local CLOUDFLARED_URL=""
    case "$ARCH" in
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
    if command -v opencode >/dev/null 2>&1; then
        echo "opencode"
    elif [ -f "$HOME/.local/bin/opencode" ]; then
        echo "$HOME/.local/bin/opencode"
    elif [ -f "/usr/local/bin/opencode" ]; then
        echo "/usr/local/bin/opencode"
    else
        echo ""
    fi
}

start_services() {
    local OPENCODE_PORT="${1:-56780}"
    local OPENCODE_USER="${2:-opencode}"
    local OPENCODE_PASSWORD="${3:-}"
    local CLOUDFLARED_TOKEN="${4:-}"
    local PUBLIC_HOSTNAME="${5:-}"

    # persist custom hostname (optional)
    if [ -n "$PUBLIC_HOSTNAME" ]; then
        save_public_hostname "$PUBLIC_HOSTNAME"
    fi

    _cleanup_on_error() {
        local rc=$?
        log_error "安装/启动过程中发生错误，正在回滚（停止已启动的进程）..."
        stop_services || true
        exit $rc
    }
    trap _cleanup_on_error ERR INT TERM

    local port_in_use=0
    if command -v ss >/dev/null 2>&1; then
        if ss -ltnp 2>/dev/null | grep -qE ":${OPENCODE_PORT}[[:space:]]"; then
            port_in_use=1
        fi
    fi
    if [ "$port_in_use" -eq 0 ] && command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -qE ":${OPENCODE_PORT}[[:space:]]"; then
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
    export OPENCODE_SERVER_USERNAME="$OPENCODE_USER"
    if [ -n "$OPENCODE_PASSWORD" ]; then
        export OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD"
    else
        unset OPENCODE_SERVER_PASSWORD || true
    fi

    check_root
    check_dependencies
    install_opencode
    download_cloudflared

    local OPENCODE_BIN
    OPENCODE_BIN="$(find_opencode_bin)"
    if [ -z "$OPENCODE_BIN" ]; then
        log_error "未找到 OpenCode 可执行文件"
        exit 1
    fi

    rotate_log "$OPENCODE_LOG_FILE"
    rotate_log "$CLOUDFLARED_LOG_FILE"

    log_info "启动 OpenCode 服务 (端口: $OPENCODE_PORT)..."

    if [ -f "$OPENCODE_PID_FILE" ]; then
        local OLD_PID
        OLD_PID="$(cat "$OPENCODE_PID_FILE" 2>/dev/null || true)"
        if [ -n "${OLD_PID:-}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    nohup "$OPENCODE_BIN" serve --port "$OPENCODE_PORT" >> "$OPENCODE_LOG_FILE" 2>&1 &
    local OPENCODE_PID=$!
    echo "$OPENCODE_PID" > "$OPENCODE_PID_FILE"

    sleep 3
    if kill -0 "$OPENCODE_PID" 2>/dev/null; then
        log_success "OpenCode 已启动 (PID: $OPENCODE_PID)"
    else
        log_error "OpenCode 启动失败"
        log_info "查看日志: tail -f $OPENCODE_LOG_FILE"
        exit 1
    fi

    # Health check (OpenCode server) - /global/health
    log_info "执行健康检查: /global/health"
    local HEALTH_URL="http://127.0.0.1:${OPENCODE_PORT}/global/health"
    local HEALTH_OK=0

    if command -v curl >/dev/null 2>&1; then
        for _ in 1 2 3 4 5; do
            if [ -n "$OPENCODE_PASSWORD" ]; then
                if curl -fsS -u "${OPENCODE_USER}:${OPENCODE_PASSWORD}" "$HEALTH_URL" >/dev/null 2>&1; then
                    HEALTH_OK=1
                    break
                fi
            else
                if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
                    HEALTH_OK=1
                    break
                fi
            fi
            sleep 1
        done
    fi

    if [ "$HEALTH_OK" -eq 1 ]; then
        log_success "健康检查通过"
    else
        log_warn "健康检查未通过（可能仍在启动中或认证/网络限制）。你可以稍后手动访问: $HEALTH_URL"
    fi
    # /global/health 与 /doc 是官方 Server 文档提到的常用入口。[2](https://blog.csdn.net/qq_22409661/article/details/136274442)

    log_info "启动 Cloudflare Tunnel..."

    if [ -f "$CLOUDFLARED_PID_FILE" ]; then
        local OLD_PID
        OLD_PID="$(cat "$CLOUDFLARED_PID_FILE" 2>/dev/null || true)"
        if [ -n "${OLD_PID:-}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    nohup "$OPENCODE_DIR/cloudflared" tunnel --url "http://localhost:$OPENCODE_PORT" run --token "$CLOUDFLARED_TOKEN" >> "$CLOUDFLARED_LOG_FILE" 2>&1 &
    local CLOUDFLARED_PID=$!
    echo "$CLOUDFLARED_PID" > "$CLOUDFLARED_PID_FILE"

    sleep 3
    if kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
        log_success "Cloudflared 已启动 (PID: $CLOUDFLARED_PID)"
    else
        log_error "Cloudflared 启动失败"
        log_info "查看日志: tail -f $CLOUDFLARED_LOG_FILE"
        exit 1
    fi

    sleep 1
    local SAVED_HOST
    SAVED_HOST="$(load_public_hostname)"

    echo ""
    echo "========================================"
    echo " 服务已成功启动!"
    echo "========================================"
    echo ""
    echo -e "${BLUE}服务信息:${NC}"
    echo " - OpenCode 端口: $OPENCODE_PORT"
    echo " - 登录用户名: $OPENCODE_USER"
    echo " - 登录密码: $OPENCODE_PASSWORD"
    if [ -n "${SAVED_HOST:-}" ]; then
        echo " - 自定义公网域名: ${SAVED_HOST}"
        echo " - 公网访问地址: https://${SAVED_HOST}"
    fi
    echo ""
    echo -e "${BLUE}日志文件:${NC}"
    echo " - OpenCode: $OPENCODE_LOG_FILE"
    echo " - Cloudflared: $CLOUDFLARED_LOG_FILE"
    echo ""
    echo -e "${BLUE}常用命令:${NC}"
    echo " 查看状态: bash $0 status"
    echo " 停止服务: bash $0 stop"
    echo " 重启服务: bash $0 restart"
    echo ""

    trap - ERR INT TERM
}

interactive_deploy() {
    echo "进入交互式部署模式："
    read -p "OpenCode 端口 [56780]: " OPENCODE_PORT
    OPENCODE_PORT=${OPENCODE_PORT:-56780}

    read -p "登录用户名 [opencode]: " OPENCODE_USER
    OPENCODE_USER=${OPENCODE_USER:-opencode}

    read -s -p "登录密码（留空无密码）: " OPENCODE_PASSWORD
    echo ""

    read -s -p "Cloudflare Tunnel 密钥 (-t): " CLOUDFLARED_TOKEN
    echo ""

    read -p "自定义公网域名（可选，如 app.example.com，留空跳过）: " PUBLIC_HOSTNAME
    PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME:-}

    if [ -z "$CLOUDFLARED_TOKEN" ]; then
        log_error "必须指定 Cloudflare Tunnel 密钥 (-t)；退出"
        exit 1
    fi

    start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN" "$PUBLIC_HOSTNAME"
}

stop_services() {
    log_info "停止服务..."
    local STOPPED=0

    if [ -f "$OPENCODE_PID_FILE" ]; then
        local OPENCODE_PID
        OPENCODE_PID="$(cat "$OPENCODE_PID_FILE" 2>/dev/null || true)"
        if [ -n "${OPENCODE_PID:-}" ] && kill -0 "$OPENCODE_PID" 2>/dev/null; then
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
        local CLOUDFLARED_PID
        CLOUDFLARED_PID="$(cat "$CLOUDFLARED_PID_FILE" 2>/dev/null || true)"
        if [ -n "${CLOUDFLARED_PID:-}" ] && kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
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

    if [ "$STOPPED" -eq 0 ]; then
        log_warn "没有运行的服务"
    fi
}

check_status() {
    echo "========================================"
    echo " 服务状态"
    echo "========================================"
    echo ""

    if [ -f "$OPENCODE_PID_FILE" ]; then
        local OPENCODE_PID
        OPENCODE_PID="$(cat "$OPENCODE_PID_FILE" 2>/dev/null || true)"
        if [ -n "${OPENCODE_PID:-}" ] && kill -0 "$OPENCODE_PID" 2>/dev/null; then
            echo -e "${GREEN}[运行中]${NC} OpenCode (PID: $OPENCODE_PID)"
        else
            echo -e "${RED}[已停止]${NC} OpenCode"
        fi
    else
        echo -e "${YELLOW}[未启动]${NC} OpenCode"
    fi

    if [ -f "$CLOUDFLARED_PID_FILE" ]; then
        local CLOUDFLARED_PID
        CLOUDFLARED_PID="$(cat "$CLOUDFLARED_PID_FILE" 2>/dev/null || true)"
        if [ -n "${CLOUDFLARED_PID:-}" ] && kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
            echo -e "${GREEN}[运行中]${NC} Cloudflared (PID: $CLOUDFLARED_PID)"
        else
            echo -e "${RED}[已停止]${NC} Cloudflared"
        fi
    else
        echo -e "${YELLOW}[未启动]${NC} Cloudflared"
    fi

    echo ""
    echo "========================================"
    echo " 自定义公网域名"
    echo "========================================"
    local SAVED_HOST
    SAVED_HOST="$(load_public_hostname)"
    if [ -n "${SAVED_HOST:-}" ]; then
        echo -e "${GREEN}${SAVED_HOST}${NC}"
        echo -e "${GREEN}https://${SAVED_HOST}${NC}"
    else
        echo "未配置自定义公网域名。"
        echo "你可以在 install 时通过 -H/--public-hostname 设置，或使用 interactive 模式输入。"
        echo "示例：bash $0 install -t eyJh... -H app.example.com"
    fi

    echo ""
    echo "========================================"
    echo " 日志预览"
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
    echo " 公开访问链接（trycloudflare）"
    echo "========================================"

    if [ -f "$CLOUDFLARED_LOG_FILE" ]; then
        PUBLIC_URL=$(grep -oE 'https://[^[:space:]]+\.trycloudflare\.com' "$CLOUDFLARED_LOG_FILE" 2>/dev/null | tail -1)

        if [ -n "${PUBLIC_URL:-}" ]; then
            echo -e "${GREEN}${PUBLIC_URL}${NC}"
            echo "(提示：该链接通常来自 Quick Tunnel/临时隧道模式)"
        else
            echo "未检测到 trycloudflare 临时链接。"
            echo "(提示：Token 隧道模式下，公网地址通常是你在 Zero Trust 控制台配置的 Public Hostname/自定义域名。)"
        fi
    else
        echo "未找到 Cloudflared 日志"
    fi

    echo ""
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        print_help
        exit 0
    fi

    if [ $# -eq 0 ]; then
        print_help
        exit 0
    fi

    local COMMAND=""
    local OPENCODE_PORT="56780"
    local OPENCODE_USER="opencode"
    local OPENCODE_PASSWORD=""
    local CLOUDFLARED_TOKEN=""
    local PUBLIC_HOSTNAME=""

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
            -H|--public-hostname)
                PUBLIC_HOSTNAME="$2"
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
            start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN" "$PUBLIC_HOSTNAME"
            ;;
        interactive)
            interactive_deploy
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
            start_services "$OPENCODE_PORT" "$OPENCODE_USER" "$OPENCODE_PASSWORD" "$CLOUDFLARED_TOKEN" "$PUBLIC_HOSTNAME"
            ;;
        *)
            log_error "未知命令: $COMMAND"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
