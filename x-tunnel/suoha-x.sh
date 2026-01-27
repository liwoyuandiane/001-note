#!/bin/bash
# suoha-x.sh - 修复交互式输入逻辑（逐行输入，避免混输）
set -euo pipefail
trap 'echo "❌ 步骤失败：$BASH_COMMAND"' ERR

# 系统适配 + 包名映射
declare -A os_configs=(
    ["Debian"]="apt update && apt install -y"
    ["Ubuntu"]="apt update && apt install -y"
    ["CentOS"]="yum install -y"
    ["Fedora"]="yum install -y"
    ["Amazon"]="yum install -y"
    ["Alpine"]="apk add -f"
)
declare -A pkg_names=(
    ["curl"]="curl"
    ["screen"]="screen"
    ["lsof"]="lsof"
    ["procps"]="procps"
    ["chmod"]="coreutils"
    ["mkdir"]="coreutils"
    ["rm"]="coreutils"
    ["grep"]="grep"
    ["cut"]="coreutils"
    ["tr"]="coreutils"
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
use_cf=0
pkg_manager=""

# 增强版系统识别
detect_os() {
    echo "🔍 识别系统..."
    local os_release="/etc/os-release"
    if [ -f "$os_release" ]; then
        local os_id=$(grep -E '^ID=' "$os_release" | cut -d= -f2 | tr -d '"')
        local os_id_like=$(grep -E '^ID_LIKE=' "$os_release" | cut -d= -f2 | tr -d '"')
        if [[ $os_id == "debian" || $os_id_like == *"debian"* ]]; then
            pkg_manager="${os_configs["Debian"]}"
        elif [[ $os_id == "centos" || $os_id == "fedora" || $os_id == "amzn" ]]; then
            pkg_manager="${os_configs["CentOS"]}"
        elif [[ $os_id == "alpine" ]]; then
            pkg_manager="${os_configs["Alpine"]}"
        else
            pkg_manager="${os_configs["Debian"]}"
        fi
    else
        pkg_manager="${os_configs["Debian"]}"
    fi
}

# 安装基础命令
install_basic_commands() {
    local needed_cmds=("curl" "screen" "lsof" "procps")
    local missing_pkgs=()
    echo "🔍 检查基础命令..."
    for cmd in "${needed_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_pkgs+=("${pkg_names[$cmd]}")
        fi
    done
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        detect_os
        if [[ $pkg_manager == *"apt"* ]]; then
            echo "📦 更新apt源..."
            apt update -y &> /dev/null
        fi
        local unique_pkgs=($(echo "${missing_pkgs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
        echo "📦 安装缺失包：${unique_pkgs[*]}"
        eval "$pkg_manager ${unique_pkgs[*]}"
    fi
    echo "✅ 基础命令已就绪"
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
}

# 核心部署
quicktunnel() {
    # 1. 下载程序
    echo "⬇️ 下载程序文件..."
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) suffix="amd64";;
        i386|i686) suffix="386";;
        arm64|aarch64) suffix="arm64";;
        *) echo "❌ 不支持的架构"; exit 1;;
    esac
    download() {
        local url=$1 out=$2
        [ -f "$out" ] && return
        curl -L --connect-timeout 30 --retry 3 "$url" -o "$out"
        chmod +x "$out"
    }
    download "https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-${suffix}" "x-tunnel-linux"
    download "https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-${suffix}" "opera-linux"
    download "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${suffix}" "cloudflared-linux"

    # 2. 启动x-tunnel
    echo "🚀 启动x-tunnel..."
    local wsport=$(get_free_port)
    local xtunnel_cmd="./x-tunnel-linux -l ws://127.0.0.1:$wsport"
    [ -n "$xtoken" ] && xtunnel_cmd+=" -token $xtoken"
    screen -dmUS x-tunnel "$xtunnel_cmd"
    sleep 2

    # 3. 启动CF隧道
    echo "🚀 启动Cloudflare隧道..."
    local metric_port=$(get_free_port)
    if [ "$use_cf" = "1" ]; then
        # 固定隧道配置
        local creds_file="/root/.cloudflared/${tunnel_id}.json"
        mkdir -p /root/.cloudflared
        cat > "$creds_file" << EOF
{
  "AccountTag": "${account_tag}",
  "TunnelSecret": "${tunnel_secret}",
  "TunnelID": "${tunnel_id}"
}
EOF
        chmod 600 "$creds_file"
        cat > config.yml << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}
ingress:
  - hostname: ${cf_domain}
    service: http://127.0.0.1:${wsport}
  - service: http_status:404
EOF
        argo_cmd="./cloudflared-linux --edge-ip-version $ips --region $region tunnel run --config config.yml --metrics 0.0.0.0:$metric_port"
    else
        # 快速隧道
        argo_cmd="./cloudflared-linux --edge-ip-version $ips tunnel --url 127.0.0.1:$wsport --metrics 0.0.0.0:$metric_port"
    fi
    screen -dmUS argo "$argo_cmd"
    sleep 5

    # 4. 输出访问地址
    echo -e "\n🎉 部署成功！"
    if [ "$use_cf" = "1" ]; then
        echo "🔗 访问地址：$cf_domain:443"
    else
        # 提取快速隧道临时域名
        while true; do
            local resp=$(curl -s "http://127.0.0.1:$metric_port/metrics")
            if echo "$resp" | grep -q 'userHostname='; then
                local domain=$(echo "$resp" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                echo "🔗 临时访问地址：$domain:443（重启失效）"
                break
            fi
            sleep 1
        done
    fi
    echo "📜 查看日志：screen -r argo"
    echo "📊 查看状态：./suoha-x.sh status"
}

# 查看状态
check_status() {
    echo -e "\n📊 服务状态："
    for srv in x-tunnel opera argo; do
        screen -list | grep -q "$srv" && echo "✅ $srv：运行中" || echo "❌ $srv：已停止"
    done
}

# 交互式逻辑（核心：逐行输入，强制回车）
original_interactive() {
    clear
    echo "===== 梭哈模式（逐行输入，请勿混输）====="
    echo "快速隧道：重启失效（默认） | 固定隧道：永久有效"
    echo -e "================================
