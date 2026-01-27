#!/bin/bash

set -euo pipefail

set -e

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

print_help() {
    echo "========================================"
    echo "    OpenCode + Cloudflared 安装脚本    "
    echo "           Version $SCRIPT_VERSION            "
    echo "========================================"
    echo ""
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install                   安装并启动服务"
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
    echo "  $0 install -t eyJh..."
    echo "  $0 install -P YourPassword123 -t eyJh..."
    echo "  $0 install -p 8080 -u admin -P YourPassword123 -t eyJh..."
    echo "  $0 status"
    echo "  $0 stop"
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

    if command -v opencode &> /dev/null; then
        log_success "OpenCode 已安装"
    else
        curl -fsSL https://opencode.ai/install | bash 2>&1 | tee -a "$OPENCODE_LOG_FILE"
        export PATH="$HOME/.local/bin:$PATH"

        if command -v opencode &> /dev/null; then
            log_success "OpenCode 安装成功"
        else
            log_error "OpenCode 安装失败，请手动安装"
            log_info "访问 https://opencode.ai 获取安装帮助"
            return 1
        fi
    fi
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
    if command -v opencode &> /dev/null; then
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
    OPENCODE_PORT="${1:-56780}"
    OPENCODE_USER="${2:-opencode}"
    OPENCODE_PASSWORD="$3"
    CLOUDFLARED_TOKEN="$4"

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

    log_info "启动 OpenCode 服务 (端口: $OPENCODE_PORT)..."

    if [ -f "$OPENCODE_PID_FILE" ]; then
        OLD_PID=$(cat "$OPENCODE_PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    nohup "$OPENCODE_BIN" serve --port "$OPENCODE_PORT" > "$OPENCODE_LOG_FILE" 2>&1 &
    OPENCODE_PID=$!
    echo $OPENCODE_PID > "$OPENCODE_PID_FILE"

    sleep 3
    if kill -0 $OPENCODE_PID 2>/dev/null; then
        log_success "OpenCode 已启动 (PID: $OPENCODE_PID)"
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

    nohup "$OPENCODE_DIR/cloudflared" tunnel --url "http://localhost:$OPENCODE_PORT" run --token "$CLOUDFLARED_TOKEN" > "$CLOUDFLARED_LOG_FILE" 2>&1 &
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
        else
            echo "等待 Cloudflared 生成链接... (可能需要10-30秒)"
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
            install|status|stop|restart)
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
        *)
            log_error "未知命令: $COMMAND"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
