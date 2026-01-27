#!/bin/bash
# suoha x-tunnel - 全自动版（自动识别系统+自动安装依赖）
# 使用方式1（交互式）：./suoha-x.sh
# 使用方式2（参数驱动）：
#   ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x xtoken] [-a account_tag] [-s tunnel_secret] [-i tunnel_id] [-d cfdomain] [-r region]
#     -a: Cloudflare AccountTag（必填）
#     -s: Cloudflare TunnelSecret（必填）
#     -i: Cloudflare TunnelID（必填）
#     -d: 固定隧道绑定的自定义域名（必填）
#     -r: CF节点区域（us/eu/asia，默认us）

# 仅在关键业务逻辑生效（避免依赖安装失败就退出）
set -euo pipefail
trap 'echo "❌ 步骤执行失败：$BASH_COMMAND"' ERR

# ====================== 1. 通用变量 ======================
# 系统适配（增强识别：支持Amazon Linux/统信UOS等）
declare -A os_configs=(
    ["Debian"]="apt update && apt install -y"
    ["Ubuntu"]="apt update && apt install -y"
    ["CentOS"]="yum install -y"
    ["Fedora"]="yum install -y"
    ["Amazon"]="yum install -y"  # Amazon Linux归为CentOS系
    ["Alpine"]="apk add -f"
    ["RHEL"]="yum install -y"
)

# 默认参数
opera=0
ips=4
xtoken=""
account_tag=""
tunnel_secret=""
tunnel_id=""
cf_domain=""
region="us"
country="AM"
pkg_manager=""  # 自动识别的包管理器命令

# ====================== 2. 核心函数（全自动依赖安装） ======================
# 增强版系统识别（解决之前识别失败问题）
detect_os() {
    echo "🔍 识别系统发行版..."
    local os_release="/etc/os-release"
    if [ -f "$os_release" ]; then
        # 优先识别ID_LIKE/ID字段（更准确）
        local os_id=$(grep -E '^ID=' "$os_release" | cut -d= -f2 | tr -d '"')
        local os_id_like=$(grep -E '^ID_LIKE=' "$os_release" | cut -d= -f2 | tr -d '"')

        # 匹配包管理器
        if [[ $os_id == "debian" || $os_id_like == *"debian"* ]]; then
            pkg_manager="${os_configs["Debian"]}"
            echo "✅ 识别为Debian/Ubuntu系，包管理器：apt"
        elif [[ $os_id == "centos" || $os_id == "fedora" || $os_id == "amzn" || $os_id_like == *"rhel"* ]]; then
            pkg_manager="${os_configs["CentOS"]}"
            echo "✅ 识别为CentOS/Fedora/Amazon Linux系，包管理器：yum"
        elif [[ $os_id == "alpine" ]]; then
            pkg_manager="${os_configs["Alpine"]}"
            echo "✅ 识别为Alpine系，包管理器：apk"
        else
            echo "⚠️ 未识别到系统，尝试用apt安装（通用兼容）"
            pkg_manager="${os_configs["Debian"]}"
        fi
    else
        echo "⚠️ 无法读取系统信息，尝试用apt安装"
        pkg_manager="${os_configs["Debian"]}"
    fi
}

# 全自动安装基础命令（失败重试+容错）
install_basic_commands() {
    local needed_cmds=("curl" "screen" "lsof" "ps" "chmod" "mkdir" "rm" "grep" "cut" "tr")
    local missing_cmds=()

    # 检查缺失命令
    for cmd in "${needed_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    # 无缺失则跳过
    if [ ${#missing_cmds[@]} -eq 0 ]; then
        echo "✅ 所有基础命令已安装"
        return
    fi

    # 自动安装缺失命令
    echo "📦 缺少命令：${missing_cmds[*]}，自动安装..."
    detect_os

    # 执行安装（增加重试机制）
    local retry=3
    while [ $retry -gt 0 ]; do
        echo "尝试安装（剩余重试次数：$retry）..."
        if eval "$pkg_manager ${missing_cmds[*]}"; then
            echo "✅ 基础命令安装成功"
            return
        fi
        retry=$((retry-1))
        sleep 2
    done

    # 安装失败仍尝试继续（避免直接退出）
    echo "⚠️ 部分命令安装失败，但继续执行（可能影响后续功能）"
}

# 获取空闲端口
get_free_port() {
    while true; do
        local PORT=$((RANDOM + 1024))
        if ! lsof -i TCP:"$PORT" &> /dev/null; then
            echo "$PORT"
            return
        fi
    done
}

# 生成CF配置（自动设600权限）
generate_cf_config() {
    echo "📝 生成Cloudflare隧道配置..."
    local creds_file="/root/.cloudflared/${tunnel_id}.json"
    mkdir -p /root/.cloudflared

    # 写入credentials（强制600权限）
    cat > "$creds_file" << EOF
{
  "AccountTag": "${account_tag}",
  "TunnelSecret": "${tunnel_secret}",
  "TunnelID": "${tunnel_id}"
}
EOF
    chmod 600 "$creds_file"

    # 写入config.yml
    cat > config.yml << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}
ingress:
  - hostname: ${cf_domain}
    service: http://127.0.0.1:${wsport}
  - service: http_status:404
EOF
}

# 停止服务
stop_services() {
    echo "🛑 停止所有服务..."
    screen -wipe &> /dev/null
    for srv in x-tunnel opera argo; do
        if screen -list | grep -q "$srv"; then
            screen -S "$srv" -X quit &> /dev/null
            sleep 1
        fi
    done
    [ -f config.yml ] && rm -f config.yml
    echo "✅ 服务已停止"
}

# 核心部署逻辑
quicktunnel() {
    # 校验必填参数
    if [[ -z "$account_tag" || -z "$tunnel_secret" || -z "$tunnel_id" || -z "$cf_domain" ]]; then
        echo "❌ 错误：CF固定隧道参数不完整！"
        exit 1
    fi

    # 1. 下载程序（超时重试）
    echo "⬇️ 下载程序文件..."
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) local suffix="amd64";;
        i386|i686) local suffix="386";;
        arm64|aarch64) local suffix="arm64";;
        *) echo "❌ 不支持的架构：$arch"; exit 1;;
    esac

    # 下载函数（带超时）
    download() {
        local url=$1 out=$2
        [ -f "$out" ] && return
        curl -L --connect-timeout 30 --retry 3 "$url" -o "$out"
        chmod +x "$out"
    }

    download "https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-${suffix}" "x-tunnel-linux"
    download "https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-${suffix}" "opera-linux"
    download "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${suffix}" "cloudflared-linux"

    # 2. 启动opera（可选）
    if [ "$opera" = "1" ]; then
        echo "🚀 启动Opera代理..."
        local operaport=$(get_free_port)
        screen -dmUS opera ./opera-linux -country "$country" -socks-mode -bind-address "127.0.0.1:$operaport"
        sleep 2
    fi

    # 3. 启动x-tunnel
    echo "🚀 启动x-tunnel..."
    local wsport=$(get_free_port)
    local xtunnel_cmd="./x-tunnel-linux -l ws://127.0.0.1:$wsport"
    [ -n "$xtoken" ] && xtunnel_cmd+=" -token $xtoken"
    [ "$opera" = "1" ] && xtunnel_cmd+=" -f socks5://127.0.0.1:$operaport"
    screen -dmUS x-tunnel "$xtunnel_cmd"
    sleep 2

    # 4. 启动CF隧道
    echo "🚀 启动Cloudflare固定隧道..."
    generate_cf_config
    local metric_port=$(get_free_port)
    local argo_cmd="./cloudflared-linux --edge-ip-version $ips --region $region --protocol http2 tunnel run --config config.yml --metrics 0.0.0.0:$metric_port"
    screen -dmUS argo "$argo_cmd"
    sleep 5

    # 5. 部署成功提示
    echo -e "\n🎉 部署完成！"
    echo "🔗 访问地址：$cf_domain:443"
    echo "📜 查看CF日志：screen -r argo"
    echo "📊 查看状态：./suoha-x.sh status"
}

# 查看状态
check_status() {
    echo -e "\n📊 服务状态："
    for srv in x-tunnel opera argo; do
        if screen -list | grep -q "$srv"; then
            echo "✅ $srv：运行中"
        else
            echo "❌ $srv：已停止"
        fi
    done
}

# ====================== 3. 交互式逻辑 ======================
original_interactive() {
    clear
    echo "===== 梭哈模式（全自动部署）====="
    echo "快速隧道：重启失效 | 固定隧道：永久有效"
    echo -e "===================================\n"
    read -p "请选择（1=部署/2=停止/3=清空缓存/0=退出，默认1）：" mode
    [ -z "$mode" ] && mode=1

    case $mode in
        1)
            # 基础参数
            read -p "是否启用opera代理(0=否/1=是，默认0)：" opera
            read -p "IP版本(4/6，默认4)：" ips
            read -p "x-tunnel Token（可选）：" xtoken
            read -p "使用CF固定隧道？(0=快速/1=固定，默认1)：" use_cf
            [ -z "$use_cf" ] && use_cf=1

            # CF固定隧道参数
            if [ "$use_cf" = "1" ]; then
                echo -e "\n📝 请输入CF固定隧道参数（从后台复制）："
                read -p "AccountTag：" account_tag
                read -p "TunnelSecret：" tunnel_secret
                read -p "TunnelID：" tunnel_id
                read -p "绑定域名：" cf_domain
                read -p "CF节点区域(us/eu/asia，默认us)：" region
            fi

            # 自动安装依赖 + 部署
            install_basic_commands
            stop_services
            quicktunnel
            ;;
        2) stop_services ;;
        3)
            stop_services
            rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml /root/.cloudflared/*.json
            echo "✅ 缓存已清空"
            ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项"; exit 1 ;;
    esac
}

# ====================== 4. 主逻辑 ======================
case "${1:-}" in
    install)
        shift
        # 解析参数
        while getopts "o:c:x:a:s:i:d:r:" opt; do
            case $opt in
                o) opera=$OPTARG ;;
                c) ips=$OPTARG ;;
                x) xtoken=$OPTARG ;;
                a) account_tag=$OPTARG ;;
                s) tunnel_secret=$OPTARG ;;
                i) tunnel_id=$OPTARG ;;
                d) cf_domain=$OPTARG ;;
                r) region=$OPTARG ;;
                *) echo "❌ 用法：$0 install -a <AccountTag> -s <TunnelSecret> -i <TunnelID> -d <域名>"; exit 1 ;;
            esac
        done
        install_basic_commands
        stop_services
        quicktunnel
        ;;
    stop) stop_services ;;
    remove)
        stop_services
        rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml /root/.cloudflared/*.json
        echo "✅ 缓存已清空"
        ;;
    status) check_status ;;
    *) original_interactive ;;
esac
