#!/bin/bash
# suoha x-tunnel - 命令行参数版（支持cloudflared持久化隧道令牌）
# 使用方式:
# ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x token值] [-t cloudflared令牌]  # 安装部署
# ./suoha-x.sh stop                                   # 停止服务
# ./suoha-x.sh remove                                 # 清空缓存/卸载
# ./suoha-x.sh status                                 # 查看运行状态

# ====================== 1. 定义变量和默认值 ======================
# 系统适配数组
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

# 默认参数值
opera=0          # 默认不启用opera代理
ips=4            # 默认IPv4
token=""         # x-tunnel的token，默认无
country="AM"     # opera默认地区
tunnel_token=""  # cloudflared隧道令牌，默认空（使用临时隧道）

# ====================== 2. 核心函数定义 ======================
# 获取空闲端口
get_free_port() {
    while true; do
        PORT=$((RANDOM + 1024))  # 避免系统保留端口
        if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
            echo $PORT
            return
        fi
    done
}

# 检测系统并匹配包管理器
detect_os() {
    n=0
    os_name=$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')
    for i in "${linux_os[@]}"; do
        if [ "$i" == "$os_name" ]; then
            break
        else
            n=$[$n+1]
        fi
    done
    if [ $n == 5 ]; then
        echo "当前系统$os_name没有适配，默认使用APT包管理器"
        n=0
    fi
}

# 安装依赖
install_deps() {
    # 检查并安装screen
    if [ -z $(type -P screen) ]; then
        echo "正在安装screen..."
        ${linux_update[$n]}
        ${linux_install[$n]} screen
    fi
    # 检查并安装curl
    if [ -z $(type -P curl) ]; then
        echo "正在安装curl..."
        ${linux_update[$n]}
        ${linux_install[$n]} curl
    fi
    # 检查并安装lsof（get_free_port需要）
    if [ -z $(type -P lsof) ]; then
        echo "正在安装lsof..."
        ${linux_update[$n]}
        ${linux_install[$n]} lsof
    fi
}

# 下载并启动代理程序
quicktunnel() {
    echo "检测CPU架构并下载程序..."
    case "$(uname -m)" in
        x86_64 | x64 | amd64 )
            [ ! -f "x-tunnel-linux" ] && curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-amd64 -o x-tunnel-linux
            [ ! -f "opera-linux" ] && curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-amd64 -o opera-linux
            [ ! -f "cloudflared-linux" ] && curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
            ;;
        i386 | i686 )
            [ ! -f "x-tunnel-linux" ] && curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-386 -o x-tunnel-linux
            [ ! -f "opera-linux" ] && curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-386 -o opera-linux
            [ ! -f "cloudflared-linux" ] && curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
            ;;
        armv8 | arm64 | aarch64 )
            [ ! -f "x-tunnel-linux" ] && curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-arm64 -o x-tunnel-linux
            [ ! -f "opera-linux" ] && curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-arm64 -o opera-linux
            [ ! -f "cloudflared-linux" ] && curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
            ;;
        * )
            echo "当前架构$(uname -m)没有适配，退出！"
            exit 1
            ;;
    esac

    # 添加执行权限
    chmod +x cloudflared-linux x-tunnel-linux opera-linux

    # 启动opera代理（如果启用）
    if [ "$opera" = "1" ]; then
        echo "启动opera前置代理（地区：$country）..."
        operaport=$(get_free_port)
        screen -dmUS opera ./opera-linux -country $country -socks-mode -bind-address "127.0.0.1:$operaport"
        sleep 1
    fi

    # 启动x-tunnel
    echo "启动x-tunnel代理..."
    wsport=$(get_free_port)
    if [ -z "$token" ]; then
        if [ "$opera" = "1" ]; then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport
        fi
    else
        if [ "$opera" = "1" ]; then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $token -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $token
        fi
    fi
    sleep 1

    # 启动cloudflared（区分临时隧道/持久化隧道）
    echo "启动Cloudflare隧道..."
    metricsport=$(get_free_port)
    ./cloudflared-linux update >/dev/null 2>&1
    
    if [ -n "$tunnel_token" ]; then
        # 有隧道令牌：使用持久化隧道
        echo "使用指定的cloudflared令牌启动持久化隧道..."
        screen -dmUS argo ./cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel run --token "$tunnel_token" --metrics 0.0.0.0:$metricsport
    else
        # 无令牌：使用临时Argo快速隧道
        echo "启动临时Argo快速隧道..."
        screen -dmUS argo ./cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --url 127.0.0.1:$wsport --metrics 0.0.0.0:$metricsport
    fi

    # 提取隧道域名（兼容临时/持久化隧道）
    echo "正在获取Cloudflare隧道公网域名..."
    while true; do
        RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics")
        if echo "$RESP" | grep -q 'userHostname='; then
            DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
            echo "✅ 部署成功！"
            if [ -z "$token" ]; then
                echo "访问链接：$DOMAIN:443（无x-tunnel token）"
            else
                echo "访问链接：$DOMAIN:443 | x-tunnel身份令牌：$token"
            fi
            if [ -n "$tunnel_token" ]; then
                echo "隧道类型：持久化隧道（使用指定令牌）"
            else
                echo "隧道类型：临时Argo快速隧道（重启失效）"
            fi
            echo "Metrics地址：http://$(curl -4 -s https://www.cloudflare.com/cdn-cgi/trace | grep ip= | cut -d= -f2):$metricsport/metrics"
            break
        else
            sleep 1
        fi
    done
}

# 停止所有服务
stop_services() {
    echo "正在停止所有服务..."
    screen -wipe >/dev/null 2>&1
    # 停止x-tunnel
    if screen -list | grep -q "x-tunnel"; then
        screen -S x-tunnel -X quit
        while screen -list | grep -q "x-tunnel"; do
            echo "等待x-tunnel退出..."
            sleep 1
        done
    fi
    # 停止opera
    if screen -list | grep -q "opera"; then
        screen -S opera -X quit
        while screen -list | grep -q "opera"; do
            echo "等待opera退出..."
            sleep 1
        done
    fi
    # 停止argo
    if screen -list | grep -q "argo"; then
        screen -S argo -X quit
        while screen -list | grep -q "argo"; do
            echo "等待argo退出..."
            sleep 1
        done
    fi
    echo "✅ 所有服务已停止"
}

# 查看服务状态
check_status() {
    echo "===== 服务运行状态 ====="
    # 检查screen进程
    if screen -list | grep -q "x-tunnel"; then
        echo "x-tunnel：运行中"
    else
        echo "x-tunnel：已停止"
    fi
    if screen -list | grep -q "opera"; then
        echo "opera-proxy：运行中（地区：$country）"
    else
        echo "opera-proxy：已停止"
    fi
    if screen -list | grep -q "argo"; then
        echo "cloudflared：运行中（IP版本：IPv$ips）"
        # 尝试获取域名
        metricsport=$(ps aux | grep cloudflared-linux | grep metrics | awk -F':' '{print $3}' | awk '{print $1}')
        if [ ! -z "$metricsport" ]; then
            RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics")
            if echo "$RESP" | grep -q 'userHostname='; then
                DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                echo "Cloudflare隧道域名：$DOMAIN:443"
            fi
        fi
        # 显示隧道类型
        if [ -n "$tunnel_token" ]; then
            echo "隧道类型：持久化隧道（已绑定令牌）"
        else
            echo "隧道类型：临时Argo快速隧道"
        fi
    else
        echo "cloudflared：已停止"
    fi
    echo "========================"
}

# ====================== 3. 命令行参数解析 ======================
if [ $# -eq 0 ]; then
    echo "使用帮助："
    echo "  ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x token值] [-t cloudflared令牌]  # 安装部署"
    echo "    -o：是否启用opera代理（0=禁用[默认]，1=启用）"
    echo "    -c：cloudflared IP版本（4=IPv4[默认]，6=IPv6）"
    echo "    -x：x-tunnel的身份令牌（可选）"
    echo "    -t：cloudflared的隧道令牌（可选，设置后使用持久化隧道）"
    echo "  ./suoha-x.sh stop                                   # 停止所有服务"
    echo "  ./suoha-x.sh remove                                 # 停止服务并删除程序文件"
    echo "  ./suoha-x.sh status                                 # 查看服务运行状态"
    exit 1
fi

case "$1" in
    install)
        # 解析install的子参数
        shift
        while getopts "o:c:x:t:" opt; do
            case $opt in
                o)
                    opera=$OPTARG
                    # 验证opera参数合法性
                    if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
                        echo "错误：-o参数只能是0或1（0=禁用opera，1=启用opera）"
                        exit 1
                    fi
                    ;;
                c)
                    ips=$OPTARG
                    # 验证IP版本合法性
                    if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
                        echo "错误：-c参数只能是4或6（4=IPv4，6=IPv6）"
                        exit 1
                    fi
                    ;;
                x)
                    token=$OPTARG
                    ;;
                t)
                    tunnel_token=$OPTARG
                    # 验证令牌非空
                    if [ -z "$tunnel_token" ]; then
                        echo "错误：-t参数不能为空（需填写cloudflared隧道令牌）"
                        exit 1
                    fi
                    ;;
                ?)
                    echo "错误：无效参数，请查看帮助：./suoha-x.sh"
                    exit 1
                    ;;
            esac
        done

        # 执行安装流程
        detect_os
        install_deps
        stop_services  # 先停止旧服务
        quicktunnel
        ;;
    stop)
        stop_services
        ;;
    remove)
        stop_services
        echo "正在删除程序文件..."
        rm -rf cloudflared-linux x-tunnel-linux opera-linux
        echo "✅ 已清空所有缓存文件"
        ;;
    status)
        check_status
        ;;
    *)
        echo "错误：无效命令！"
        echo "使用帮助：./suoha-x.sh"
        exit 1
        ;;
esac