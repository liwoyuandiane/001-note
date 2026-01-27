#!/bin/bash
# suoha x-tunnel - 双模式版（完善Cloudflare固定隧道支持）
# 使用方式1（交互式）：./suoha-x.sh
# 使用方式2（参数驱动）：
#   ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x xtoken] [-t cftoken] [-d cfdomain]
#     -t: cloudflared固定隧道令牌
#     -d: 固定隧道绑定的自定义域名（必填，若用-t）
#   ./suoha-x.sh stop                                   # 停止服务
#   ./suoha-x.sh remove                                 # 清空缓存/卸载
#   ./suoha-x.sh status                                 # 查看运行状态

# ====================== 1. 通用变量与核心函数（复用逻辑） ======================
# 系统适配数组
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

# 默认参数（参数驱动模式用）
opera=0
ips=4
xtoken=""          # x-tunnel的token
cf_token=""        # cloudflared固定隧道令牌
cf_domain=""       # 固定隧道绑定的自定义域名（新增）
country="AM"

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

# 生成固定隧道的Ingress配置文件（新增核心函数）
generate_cf_config() {
    echo "生成cloudflared固定隧道配置文件..."
    cat > config.yml << EOF
tunnel: $(echo $cf_token | cut -d':' -f3 | cut -c1-8)  # 隧道标识（取token片段）
credentials-file: /root/.cloudflared/${cf_token: -32}.json

ingress:
  - hostname: $cf_domain
    service: http://127.0.0.1:$wsport  # 转发到x-tunnel的ws端口
  - service: http_status:404
EOF
    # 创建cloudflared配置目录
    mkdir -p /root/.cloudflared
    # 写入token到credentials文件（固定隧道必需）
    echo "{\"AccountTag\":\"$(echo $cf_token | cut -d':' -f1)\",\"TunnelSecret\":\"$(echo $cf_token | cut -d':' -f2)\",\"TunnelID\":\"$(echo $cf_token | cut -d':' -f3)\"}" > /root/.cloudflared/${cf_token: -32}.json
}

# 停止所有服务（复用逻辑）
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
    # 清理固定隧道配置文件
    rm -f config.yml
    echo "✅ 所有服务已停止"
}

# 下载并启动代理程序（核心修改：适配固定隧道）
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
    if [ -z "$xtoken" ]; then
        if [ "$opera" = "1" ]; then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport
        fi
    else
        if [ "$opera" = "1" ]; then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $xtoken -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $xtoken
        fi
    fi
    sleep 1

    # 启动cloudflared（核心修改：区分快速隧道/固定隧道）
    echo "启动Cloudflare隧道..."
    metricsport=$(get_free_port)
    ./cloudflared-linux update >/dev/null 2>&1

    if [ -n "$cf_token" ] && [ -n "$cf_domain" ]; then
        # 有cf_token和cf_domain：使用固定隧道（带Ingress规则）
        generate_cf_config  # 生成配置文件
        echo "使用固定隧道模式（已绑定cloudflared令牌和域名）..."
        screen -dmUS argo ./cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel run --config config.yml --metrics 0.0.0.0:$metricsport
        
        # 固定隧道：直接提示用户使用绑定的域名，无需检测userHostname
        echo "✅ 部署成功！"
        if [ -z "$xtoken" ]; then
            echo "访问链接：$cf_domain:443（无x-tunnel token）"
        else
            echo "访问链接：$cf_domain:443 | x-tunnel身份令牌：$xtoken"
        fi
        echo "隧道类型：固定隧道（重启不失效）"
        echo "Metrics地址：http://$(curl -4 -s https://www.cloudflare.com/cdn-cgi/trace | grep ip= | cut -d= -f2):$metricsport/metrics"
    elif [ -n "$cf_token" ] && [ -z "$cf_domain" ]; then
        # 有token无域名：提示错误
        echo "❌ 错误：使用固定隧道必须指定绑定的自定义域名（-d参数/交互式输入）！"
        stop_services
        exit 1
    else
        # 无cf_token：使用快速隧道（原逻辑）
        echo "使用快速隧道模式（临时隧道，重启失效）..."
        screen -dmUS argo ./cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --url 127.0.0.1:$wsport --metrics 0.0.0.0:$metricsport

        # 提取快速隧道的临时域名
        echo "正在获取Argo临时域名..."
        while true; do
            RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics")
            if echo "$RESP" | grep -q 'userHostname='; then
                DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                echo "✅ 部署成功！"
                if [ -z "$xtoken" ]; then
                    echo "访问链接：$DOMAIN:443（无x-tunnel token）"
                else
                    echo "访问链接：$DOMAIN:443 | x-tunnel身份令牌：$xtoken"
                fi
                echo "隧道类型：快速隧道（重启/重运行失效）"
                echo "Metrics地址：http://$(curl -4 -s https://www.cloudflare.com/cdn-cgi/trace | grep ip= | cut -d= -f2):$metricsport/metrics"
                break
            else
                sleep 1
            fi
        done
    fi
}

# 查看服务状态（参数驱动模式用）
check_status() {
    echo "===== 服务运行状态 ====="
    # 检查screen进程
    if screen -list | grep -q "x-tunnel"; then
        echo "x-tunnel：运行中"
    else
        echo "x-tunnel：已停止"
    fi
    if screen -list | grep -q "opera"; then
        echo "opera-proxy：运行中"
    else
        echo "opera-proxy：已停止"
    fi
    if screen -list | grep -q "argo"; then
        echo "cloudflared(argo)：运行中"
        # 区分隧道类型显示域名
        if [ -n "$cf_domain" ]; then
            echo "绑定域名：$cf_domain（固定隧道）"
        else
            # 尝试获取快速隧道域名
            metricsport=$(ps aux | grep cloudflared-linux | grep metrics | awk -F':' '{print $3}' | awk '{print $1}')
            if [ ! -z "$metricsport" ]; then
                RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics")
                if echo "$RESP" | grep -q 'userHostname='; then
                    DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                    echo "临时域名：$DOMAIN（快速隧道）"
                fi
            fi
        fi
    else
        echo "cloudflared(argo)：已停止"
    fi
    echo "========================"
}

# ====================== 2. 原始交互式逻辑（新增cloudflared域名输入） ======================
original_interactive() {
    clear
    echo 梭哈模式不需要自己提供域名,使用CF ARGO QUICK TUNNEL创建快速链接
    echo 梭哈模式在重启或者脚本再次运行后失效,如果需要使用需要再次运行创建

    echo -e '\n'梭哈是一种智慧!!!梭哈!梭哈!梭哈!梭哈!梭哈!梭哈!梭哈...'\n'
    echo 1.梭哈模式
    echo 2.停止服务
    echo 3.清空缓存
    echo -e 0.退出脚本'\n'
    read -p "请选择模式(默认1):" mode
    if [ -z "$mode" ]; then
        mode=1
    fi

    if [ $mode == 1 ]; then
        # 交互式输入参数
        read -p "是否启用opera前置代理(0.不启用[默认],1.启用):" opera
        if [ -z "$opera" ]; then
            opera=0
        fi
        if [ "$opera" = "1" ]; then
            echo 注意:opera前置代理仅支持AM,AS,EU地区
            echo AM: 北美地区
            echo AS: 亚太地区
            echo EU: 欧洲地区
            read -p "请输入opera前置代理的国家代码(默认AM):" country
            if [ -z "$country" ]; then
                country=AM
            fi
            country=${country^^}
            if [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ]; then
                echo 请输入正确的opera前置代理国家代码
                exit 1
            fi
        fi
        if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
            echo 请输入正确的opera前置代理模式
            exit 1
        fi

        read -p "请选择cloudflared连接模式IPV4或者IPV6(输入4或6,默认4):" ips
        if [ -z "$ips" ]; then
            ips=4
        fi
        if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
            echo 请输入正确的cloudflared连接模式
            exit 1
        fi

        read -p "请设置x-tunnel的token(可留空):" xtoken
        # 新增：输入cloudflared令牌
        read -p "请设置cloudflared令牌以固定隧道(可选,留空则使用快速隧道):" cf_token
        # 新增：如果输入了cf_token，必须输入绑定的域名
        if [ -n "$cf_token" ]; then
            read -p "请输入固定隧道绑定的自定义域名(必填,如:test.example.com):" cf_domain
            if [ -z "$cf_domain" ]; then
                echo "❌ 错误：使用固定隧道必须填写绑定的自定义域名！"
                exit 1
            fi
        fi

        # 执行部署流程
        detect_os
        install_deps
        stop_services
        clear
        sleep 1
        quicktunnel

    elif [ $mode == 2 ]; then
        stop_services
        clear
    elif [ $mode == 3 ]; then
        stop_services
        clear
        echo "正在删除程序文件..."
        rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml
        echo "✅ 已清空所有缓存文件"
    else
        echo 退出成功
        exit 0
    fi
}

# ====================== 3. 主逻辑：判断执行模式（交互式/参数驱动） ======================
if [ $# -eq 0 ]; then
    # 无参数 → 执行原始交互式逻辑
    original_interactive
else
    # 有参数 → 执行参数驱动逻辑
    case "$1" in
        install)
            # 解析install的子参数（新增-d）
            shift
            while getopts "o:c:x:t:d:" opt; do
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
                        xtoken=$OPTARG  # x-tunnel的token
                        ;;
                    t)
                        cf_token=$OPTARG # cloudflared固定隧道令牌
                        ;;
                    d)
                        cf_domain=$OPTARG # 固定隧道绑定的自定义域名
                        ;;
                    ?)
                        echo "错误：无效参数！"
                        echo "使用帮助：./suoha-x.sh install [-o 0|1] [-c 4|6] [-x xtoken] [-t cftoken] [-d cfdomain]"
                        echo "  -o：是否启用opera（0/1，默认0）"
                        echo "  -c：IP版本（4/6，默认4）"
                        echo "  -x：x-tunnel的token（可选）"
                        echo "  -t：cloudflared固定隧道令牌（可选）"
                        echo "  -d：固定隧道绑定的自定义域名（必填，若用-t）"
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
            rm -rf cloudflared-linux x-tunnel-linux opera-linux config.yml
            echo "✅ 已清空所有缓存文件"
            ;;
        status)
            check_status
            ;;
        *)
            echo "错误：无效命令！"
            echo "使用帮助："
            echo "  交互式模式：./suoha-x.sh"
            echo "  参数驱动模式："
            echo "    ./suoha-x.sh install [-o 0|1] [-c 4|6] [-x xtoken] [-t cftoken] [-d cfdomain]"
            echo "    ./suoha-x.sh stop/remove/status"
            echo "  说明："
            echo "    -t：cloudflared固定隧道令牌（需提前在CF后台创建隧道）"
            echo "    -d：固定隧道绑定的自定义域名（使用-t时必填）"
            exit 1
            ;;
    esac
fi
