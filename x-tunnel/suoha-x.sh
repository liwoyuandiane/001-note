#!/bin/bash
# suoha x-tunnel - 最终版（手动配置CF固定隧道参数，解决连接问题）
# 使用方式1（交互式）：./suoha-x.sh
# 使用方式2（参数驱动）：
#   ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x xtoken] [-a account_tag] [-s tunnel_secret] [-i tunnel_id] [-d cfdomain] [-r region]
#     -a: Cloudflare AccountTag（隧道token第一部分，必填）
#     -s: Cloudflare TunnelSecret（隧道token第二部分，必填）
#     -i: Cloudflare TunnelID（隧道UUID，必填）
#     -d: 固定隧道绑定的自定义域名（必填）
#     -r: CF节点区域（us/eu/asia，默认us）
#   ./suoha-x.sh stop                                   # 停止服务
#   ./suoha-x.sh remove                                 # 清空缓存/卸载
#   ./suoha-x.sh status                                 # 查看运行状态

set -e  # 遇到错误立即退出

# ====================== 1. 通用变量与核心函数 ======================
# 系统适配数组
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

# 默认参数
opera=0
ips=4
xtoken=""          # x-tunnel token
account_tag=""     # CF AccountTag（手动填，必填）
tunnel_secret=""   # CF TunnelSecret（手动填，必填）
tunnel_id=""       # CF TunnelID（手动填，必填）
cf_domain=""       # 绑定的自定义域名
region="us"        # CF节点区域（us/eu/asia）
country="AM"

# 检查基础命令（新增）
check_basic_commands() {
    echo "检查基础命令..."
    needed_cmds=("curl" "screen" "lsof" "ps" "chmod" "mkdir" "rm")
    for cmd in "${needed_cmds[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo "缺少基础命令$cmd，正在安装..."
            detect_os
            ${linux_update[$n]}
            ${linux_install[$n]} $cmd || { echo "安装$cmd失败，请手动安装！"; exit 1; }
        fi
    done
}

# 获取空闲端口
get_free_port() {
    while true; do
        PORT=$((RANDOM + 1024))
        if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
            echo $PORT
            return
        fi
    done
}

# 检测系统
detect_os() {
    n=0
    os_name=$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')
    for i in "${linux_os[@]}"; do
        [ "$i" == "$os_name" ] && break || n=$[$n+1]
    done
    [ $n == 5 ] && { echo "系统$os_name未适配，默认用APT"; n=0; }
}

# 生成CF固定隧道配置（核心优化：手动参数，自动设权限）
generate_cf_config() {
    echo "生成Cloudflare固定隧道配置文件..."
    
    # 1. 创建credentials文件（强制600权限）
    creds_file="/root/.cloudflared/${tunnel_id}.json"
    mkdir -p /root/.cloudflared
    cat > $creds_file << EOF
{
  "AccountTag": "${account_tag}",
  "TunnelSecret": "${tunnel_secret}",
  "TunnelID": "${tunnel_id}"
}
EOF
    chmod 600 $creds_file  # 强制设置600权限，避免认证失败
    echo "✅ Credentials文件生成成功，权限已设为600"

    # 2. 创建config.yml
    cat > config.yml << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
  - hostname: ${cf_domain}
    service: http://127.0.0.1:${wsport}
  - service: http_status:404
EOF
    echo "✅ Config.yml生成成功"
}

# 停止所有服务
stop_services() {
    echo "正在停止所有服务..."
    screen -wipe >/dev/null 2>&1
    for srv in x-tunnel opera argo; do
        if screen -list | grep -q $srv; then
            screen -S $srv -X quit
            while screen -list | grep -q $srv; do sleep 1; done
            echo "✅ $srv服务已停止"
        fi
    done
    [ -f config.yml ] && rm -f config.yml
    echo "✅ 所有服务已停止"
}

# 下载并启动代理程序（核心优化：手动CF参数+节点区域）
quicktunnel() {
    # 1. 检查CF必填参数
    if [ -z "$account_tag" ] || [ -z "$tunnel_secret" ] || [ -z "$tunnel_id" ] || [ -z "$cf_domain" ]; then
        echo "❌ 错误：CF固定隧道参数不完整！"
        echo "需要：AccountTag(-a)、TunnelSecret(-s)、TunnelID(-i)、域名(-d)"
        exit 1
    fi

    # 2. 下载程序
    echo "检测CPU架构并下载程序..."
    arch=$(uname -m)
    case $arch in
        x86_64|x64|amd64)    suffix="amd64";;
        i386|i686)           suffix="386";;
        armv8|arm64|aarch64) suffix="arm64";;
        *) echo "❌ 架构$arch不支持"; exit 1;;
    esac

    # 下载二进制文件（加超时重试）
    download() {
        url=$1
        out=$2
        [ -f $out ] && return
        echo "下载$out..."
        curl -L --connect-timeout 30 --retry 3 $url -o $out || { echo "下载$out失败"; exit 1; }
        chmod +x $out
    }

    download "https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-${suffix}" "x-tunnel-linux"
    download "https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-${suffix}" "opera-linux"
    download "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${suffix}" "cloudflared-linux"

    # 3. 启动opera（如果启用）
    if [ "$opera" = "1" ]; then
        echo "启动opera前置代理（地区：$country）..."
        operaport=$(get_free_port)
        screen -dmUS opera ./opera-linux -country $country -socks-mode -bind-address "127.0.0.1:$operaport"
        sleep 2
    fi

    # 4. 启动x-tunnel
    echo "启动x-tunnel代理..."
    wsport=$(get_free_port)
    xtunnel_cmd="./x-tunnel-linux -l ws://127.0.0.1:$wsport"
    [ -n "$xtoken" ] && xtunnel_cmd+=" -token $xtoken"
    [ "$opera" = "1" ] && xtunnel_cmd+=" -f socks5://127.0.0.1:$operaport"
    screen -dmUS x-tunnel $xtunnel_cmd
    sleep 2

    # 5. 生成CF配置并启动cloudflared（核心优化：节点区域+详细日志）
    generate_cf_config
    echo "启动Cloudflare隧道（节点区域：$region）..."
    argo_cmd="./cloudflared-linux --edge-ip-version $ips --region $region --protocol http2 tunnel run --config config.yml --metrics 0.0.0.0:$(get_free_port)"
    screen -dmUS argo $argo_cmd
    sleep 5

    # 6. 验证cloudflared是否启动成功
    if ! screen -list | grep -q argo; then
        echo "❌ Cloudflared启动失败！查看日志：screen -r argo"
        exit 1
    fi

    # 7. 输出最终信息
    echo -e "\n==================== 部署成功 ===================="
    echo "✅ x-tunnel运行中（端口：$wsport）"
    [ "$opera" = "1" ] && echo "✅ Opera代理运行中（端口：$operaport）"
    echo "✅ Cloudflare固定隧道运行中（节点：$region）"
    echo "🔗 访问链接：$cf_domain:443"
    [ -n "$xtoken" ] && echo "🔑 x-tunnel Token：$xtoken"
    echo "📝 查看CF日志：screen -r argo"
    echo "=================================================="
}

# 查看服务状态
check_status() {
    echo -e "\n===== 服务运行状态 ====="
    for srv in x-tunnel opera argo; do
        if screen -list | grep -q $srv; then
            echo "✅ $srv：运行中"
            [ $srv = "argo" ] && echo "   绑定域名：$cf_domain（固定隧道，节点：$region）"
        else
            echo "❌ $srv：已停止"
        fi
    done
    echo "========================"
}

# ====================== 2. 交互式逻辑（新增手动CF参数输入） ======================
original_interactive() {
    clear
    echo "===== 梭哈模式（支持Cloudflare固定隧道）====="
    echo "快速隧道：重启失效 | 固定隧道：需手动填写CF参数"
    echo -e "===========================================\n"
    echo "1. 梭哈模式（快速隧道/固定隧道）"
    echo "2. 停止服务"
    echo "3. 清空缓存"
    echo "0. 退出脚本"
    read -p "请选择（默认1）：" mode
    [ -z "$mode" ] && mode=1

    if [ $mode == 1 ]; then
        # 基础参数
        read -p "是否启用opera前置代理(0=否[默认],1=是)：" opera
        [ -z "$opera" ] && opera=0
        [ "$opera" = "1" ] && {
            read -p "Opera地区(AM/AS/EU，默认AM)：" country
            [ -z "$country" ] && country=AM
            country=${country^^}
            [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ] && { echo "地区错误"; exit 1; }
        }
        read -p "IP版本(4/6，默认4)：" ips
        [ -z "$ips" ] && ips=4
        read -p "x-tunnel Token（可选）：" xtoken

        # 固定隧道参数（手动输入，核心优化）
        read -p "是否使用Cloudflare固定隧道？(0=快速隧道[默认],1=固定隧道)：" use_cf_tunnel
        [ -z "$use_cf_tunnel" ] && use_cf_tunnel=0

        if [ "$use_cf_tunnel" = "1" ]; then
            echo -e "\n===== 请填写Cloudflare固定隧道参数（从CF后台复制）====="
            read -p "AccountTag（token第一部分）：" account_tag
            read -p "TunnelSecret（token第二部分）：" tunnel_secret
            read -p "TunnelID（隧道UUID）：" tunnel_id
            read -p "绑定的自定义域名（如x-tunnel-1.jiedian.de5.net）：" cf_domain
            read -p "CF节点区域（us/eu/asia，默认us）：" region
            [ -z "$region" ] && region="us"
        fi

        # 执行部署
        check_basic_commands
        detect_os
        stop_services
        quicktunnel

    elif [ $mode == 2 ]; then
        stop_services
    elif [ $mode == 3 ]; then
        stop_services
        rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml /root/.cloudflared/*.json
        echo "✅ 已清空所有缓存文件"
    else
        echo "退出成功"
        exit 0
    fi
}

# ====================== 3. 主逻辑 ======================
if [ $# -eq 0 ]; then
    # 无参数 → 交互式
    original_interactive
else
    # 有参数 → 命令行模式
    case "$1" in
        install)
            shift
            # 解析参数（新增-a/-s/-i/-r）
            while getopts "o:c:x:a:s:i:d:r:" opt; do
                case $opt in
                    o) opera=$OPTARG ;;
                    c) ips=$OPTARG ;;
                    x) xtoken=$OPTARG ;;
                    a) account_tag=$OPTARG ;;  # CF AccountTag
                    s) tunnel_secret=$OPTARG ;; # CF TunnelSecret
                    i) tunnel_id=$OPTARG ;;     # CF TunnelID
                    d) cf_domain=$OPTARG ;;     # 绑定域名
                    r) region=$OPTARG ;;        # 节点区域
                    ?)
                        echo -e "\n使用帮助："
                        echo "./suoha-x.sh install -a <AccountTag> -s <TunnelSecret> -i <TunnelID> -d <域名> [可选参数]"
                        echo "  必选参数："
                        echo "    -a: Cloudflare AccountTag（隧道token第一部分）"
                        echo "    -s: Cloudflare TunnelSecret（隧道token第二部分）"
                        echo "    -i: Cloudflare TunnelID（隧道UUID）"
                        echo "    -d: 固定隧道绑定的自定义域名"
                        echo "  可选参数："
                        echo "    -o: 是否启用opera（0/1，默认0）"
                        echo "    -c: IP版本（4/6，默认4）"
                        echo "    -x: x-tunnel Token（可选）"
                        echo "    -r: CF节点区域（us/eu/asia，默认us）"
                        exit 1 ;;
                esac
            done

            # 检查基础命令 + 执行部署
            check_basic_commands
            detect_os
            stop_services
            quicktunnel
            ;;
        stop) stop_services ;;
        remove)
            stop_services
            rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml /root/.cloudflared/*.json
            echo "✅ 已清空所有缓存文件"
            ;;
        status) check_status ;;
        *)
            echo "错误：无效命令！"
            echo "使用方式："
            echo "  交互式：./suoha-x.sh"
            echo "  命令行：./suoha-x.sh install/stop/remove/status"
            exit 1 ;;
    esac
fi
