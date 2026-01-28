#!/bin/bash
#
# suoha x-tunnel - 快速隧道管理脚本
# 支持交互式模式和命令行参数模式
#
# 使用说明:
#   交互模式: ./suoha-x.sh
#   命令模式: ./suoha-x.sh <command> [options]
#
# 命令:
#   install  - 安装并启动服务
#   stop     - 停止所有服务
#   remove   - 卸载并清理所有文件
#   status   - 查看服务状态
#
# install 命令选项:
#   -o <0|1>  - 是否启用 opera 前置代理 (0:不启用, 1:启用)
#   -c <4|6>  - cloudflared 连接模式 (4:IPv4, 6:IPv6)
#   -x <token> - x-tunnel 身份令牌
#   -g <code> - opera 国家代码 (AM/AS/EU)
#   -t <token> - Cloudflare 固定隧道令牌 (可选)
#   -p <port>  - x-tunnel 监听端口 (可选，默认56789)
#   -a <token> - Cloudflare API 令牌 (可选，用于 API 自动创建或查询固定隧道域名)
#   -z <id>    - Cloudflare Zone ID (可选，用于 API 自动创建或查询固定隧道域名)
#   -d <domain>- 隧道域名 (可选，用于 API 自动创建模式)
#   -n <name>  - 隧道名称 (可选，用于 API 自动创建模式，默认: x-tunnel-auto)
#
# remove 命令选项:
#   -a <token> - Cloudflare API 令牌 (可选，用于清理 API 创建的隧道)
#   -z <id>    - Cloudflare Zone ID (可选，用于清理 API 创建的隧道)
#
# 示例:
#   # Quick Tunnel 模式
#   ./suoha-x.sh install -o 0 -c 4 -x mytoken
#
#   # 固定隧道模式
#   ./suoha-x.sh install -t "CF_Tunnel_Token" -p 56789 -o 0 -c 4 -x mytoken
#   ./suoha-x.sh install -t "CF_Tunnel_Token" -a "CF_API_Token" -z "ZONE_ID" -p 56789 -o 0 -c 4
#
#   # API 自动创建模式
#   ./suoha-x.sh install -a "YOUR_API_TOKEN" -z "YOUR_ZONE_ID" -d "tunnel.example.com" -o 0 -c 4 -x mytoken
#   ./suoha-x.sh install -a "API_TOKEN" -z "ZONE_ID" -d "tunnel.example.com" -n "my-tunnel" -o 1 -g AM -c 4
#
#   # 服务管理
#   ./suoha-x.sh stop
#   ./suoha-x.sh remove -a "API_TOKEN" -z "ZONE_ID"
#   ./suoha-x.sh status
#

# 颜色输出函数
print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m✗ $1\033[0m"
}

print_info() {
    echo -e "\033[0;36mℹ $1\033[0m"
}

print_warning() {
    echo -e "\033[0;33m⚠ $1\033[0m"
}

# API 错误处理函数 - 分析错误并显示准确的权限提示
analyze_api_error() {
    local response="$1"
    local api_name="$2"
    local errors=$(echo "$response" | grep -o '"message":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    local error_code=$(echo "$response" | grep -o '"code":[0-9]*' | head -n 1 | cut -d':' -f2)
    
    # 判断错误类型并显示详细提示
    if echo "$errors" | grep -qi "Authentication error"; then
        echo ""
        print_error "[$api_name] 认证失败: API Token 无效或权限不足"
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        echo "│                      请检查您的 Cloudflare API Token 权限                      │"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        echo "│  请登录 Cloudflare 控制台 → 我的个人资料 → API 令牌 → 编辑令牌                   │"
        echo "│                                                                             │"
        echo "│  对于当前操作，您的 Token 需要以下权限:                                        │"
        echo "│                                                                             │"
        echo "│  1. 账户权限 (Account):                                                      │"
        echo "│     • Cloudflare Tunnel: 编辑                                                │"
        echo "│                                                                             │"
        echo "│  2. 区域权限 (Zone) - 需要选择对应的 Zone:                                    │"
        echo "│     • DNS: 编辑                                                              │"
        echo "│     • Zone: 读取                                                             │"
        echo "│                                                                             │"
        echo "│  示例配置:                                                                   │"
        echo "│  账户资源: 包含(Include) → 您的账户                                          │"
        echo "│  区域资源: 包含(Include) → 特定区域 → 选择您的域名                            │"
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
        echo ""
        return 1
    fi
    
    if echo "$errors" | grep -qi "not found"; then
        echo ""
        print_error "[$api_name] 资源未找到"
        echo ""
        print_info "可能原因:"
        echo "  • Zone ID 不正确或您无权访问此 Zone"
        echo "  • Account ID 不正确"
        echo "  • 隧道不存在"
        echo ""
        return 1
    fi
    
    if echo "$errors" | grep -qi "already exists"; then
        echo ""
        print_warning "[$api_name] 资源已存在"
        return 1
    fi
    
    # 通用错误
    if [ -n "$errors" ]; then
        echo ""
        print_error "[$api_name] 错误: $errors"
        if [ -n "$error_code" ]; then
            print_info "错误代码: $error_code"
        fi
    fi
    
    return 1
}

# 解析 Cloudflare Tunnel Token
# 返回 JSON 格式的 account_id 和 tunnel_id
decode_tunnel_token() {
    local token=$1
    
    # Token 格式: <header>.<payload>.<signature>
    # 我们只需要中间的 payload 部分
    local payload=$(echo "$token" | awk -F'.' '{print $2}')
    
    # 添加 padding 并解码
    local decoded=$(echo "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$decoded"
}

# 从 Cloudflare API 获取固定隧道域名
get_tunnel_domain_from_api() {
    local tunnel_token=$1
    local api_token=$2
    local zone_id=$3

    print_info "正在从 Cloudflare API 查询隧道域名..."

    # 解析 tunnel token 获取 tunnel_id
    local token_info=$(decode_tunnel_token "$tunnel_token")
    if [ $? -ne 0 ]; then
        print_warning "无法解析隧道令牌，跳过域名查询"
        return 1
    fi

    local tunnel_id=$(echo "$token_info" | grep -o '"t":"[^"]*"' | cut -d'"' -f4)
    local account_id=$(echo "$token_info" | grep -o '"a":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$tunnel_id" ] || [ -z "$account_id" ]; then
        print_warning "无法从令牌中提取 tunnel_id 或 account_id，跳过域名查询"
        return 1
    fi

    print_info "Tunnel ID: $tunnel_id"
    print_info "Account ID: $account_id"

    # 获取 DNS 记录
    local dns_url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=CNAME"

    local response=$(curl -s --max-time 30 -X GET "$dns_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        print_warning "API 查询失败，请检查 API Token 和 Zone ID 是否正确"
        local errors=$(echo "$response" | grep -o '"message":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$errors" ]; then
            print_warning "错误信息: $errors"
        fi
        return 1
    fi

    # 查找匹配的 CNAME 记录 (更健壮的匹配方式)
    local domain=$(echo "$response" | grep -o '"content":"'"$tunnel_id"'\.cfargotunnel\.com"' -B 3 | grep -o '"name":"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -n "$domain" ]; then
        echo "$domain"
        return 0
    else
        print_warning "未找到关联的域名，请检查隧道是否已绑定到域名"
        return 1
    fi
}

# 获取 Cloudflare Account ID
get_account_id() {
    local api_token=$1

    print_info "正在获取 Account ID..."

    local api_url="https://api.cloudflare.com/client/v4/accounts"
    local response=$(curl -s --max-time 30 -X GET "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        analyze_api_error "$response" "获取 Account ID"
        return 1
    fi

    # 提取第一个 account id (从result数组中提取)
    local account_id=$(echo "$response" | grep -o '"result":\[[^\]]*\]' | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -n "$account_id" ]; then
        echo "$account_id"
        return 0
    else
        echo ""
        print_error "未找到 Account ID"
        echo ""
        print_info "可能原因:"
        echo "  • API Token 没有访问任何账户的权限"
        echo "  • 该账户尚未激活 Cloudflare 服务"
        echo ""
        print_info "请确保您的 API Token 具有以下权限:"
        echo "  • 账户: Cloudflare Tunnel → 编辑"
        echo ""
        return 1
    fi
}

# 创建 Cloudflare Tunnel
create_cloudflare_tunnel() {
    local api_token=$1
    local account_id=$2
    local tunnel_name=$3
    local reuse_mode=${4:-false}  # 是否尝试复用已存在的隧道

    print_info "正在检查隧道: $tunnel_name..."

    # 检查隧道是否已存在
    local existing_tunnel_id=$(check_tunnel_exists "$api_token" "$account_id" "$tunnel_name")

    if [ -n "$existing_tunnel_id" ]; then
        print_warning "隧道 '$tunnel_name' 已存在 (ID: $existing_tunnel_id)"

        if [ "$reuse_mode" = "true" ]; then
            # 尝试复用隧道
            print_info "尝试复用现有隧道..."
            local tunnel_token=$(get_tunnel_token "$api_token" "$account_id" "$existing_tunnel_id")

            if [ -n "$tunnel_token" ]; then
                print_success "成功复用现有隧道"
                local credentials_file="/tmp/tunnel-$existing_tunnel_id.json"
                echo "$existing_tunnel_id|$tunnel_token|$credentials_file"
                return 0
            else
                print_warning "无法获取隧道 token，将删除旧隧道并创建新隧道"
                delete_cloudflare_tunnel "$api_token" "$account_id" "$existing_tunnel_id"
                sleep 1
            fi
        else
            # 自动删除旧隧道并创建新的
            print_info "正在删除旧隧道..."
            delete_cloudflare_tunnel "$api_token" "$account_id" "$existing_tunnel_id"
            sleep 1
            print_success "旧隧道已删除，正在创建新隧道..."
        fi
    fi

    # 创建新隧道
    print_info "正在创建隧道: $tunnel_name..."

    local api_url="https://api.cloudflare.com/client/v4/accounts/$account_id/tunnels"

    local response=$(curl -s --max-time 30 -X POST "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$tunnel_name"'"
        }' 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        analyze_api_error "$response" "创建 Cloudflare Tunnel"
        return 1
    fi

    # 提取 tunnel_id 和 credentials (从result字段中提取)
    local result=$(echo "$response" | jq -r '.result' 2>/dev/null || echo "$response" | grep -o '"result":{[^}]*}' | sed 's/"result"://')
    local tunnel_id=$(echo "$result" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    local tunnel_token=$(echo "$result" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$tunnel_id" ] || [ -z "$tunnel_token" ]; then
        print_error "无法提取 tunnel_id 或 tunnel_token"
        return 1
    fi

    # 保存 credentials 到文件
    local credentials_file="/tmp/tunnel-$tunnel_id.json"
    echo "$result" > "$credentials_file"

    echo "$tunnel_id|$tunnel_token|$credentials_file"
    return 0
}

# 检查隧道是否存在
check_tunnel_exists() {
    local api_token=$1
    local account_id=$2
    local tunnel_name=$3

    local api_url="https://api.cloudflare.com/client/v4/accounts/$account_id/tunnels?name=$tunnel_name"
    local response=$(curl -s --max-time 30 -X GET "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        return 1
    fi

    # 提取 tunnel_id (从result数组中提取)
    local tunnel_id=$(echo "$response" | grep -o '"result":\[[^\]]*\]' | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -n "$tunnel_id" ] && [ "$tunnel_id" != "null" ]; then
        echo "$tunnel_id"
        return 0
    fi

    return 1
}

# 获取已有隧道的 token
get_tunnel_token() {
    local api_token=$1
    local account_id=$2
    local tunnel_id=$3

    local api_url="https://api.cloudflare.com/client/v4/accounts/$account_id/tunnels/$tunnel_id/token"
    local response=$(curl -s --max-time 30 -X POST "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local token=$(echo "$response" | jq -r '.token' 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "$token"
        return 0
    fi

    return 1
}

# 更新隧道配置 (配置 ingress 规则)
update_tunnel_config() {
    local api_token=$1
    local account_id=$2
    local tunnel_id=$3
    local hostname=$4
    local local_port=$5

    print_info "正在配置隧道 ingress: $hostname -> 127.0.0.1:$local_port..."

    local api_url="https://api.cloudflare.com/client/v4/accounts/$account_id/tunnels/$tunnel_id/configurations"
    local config_json='{
        "config": {
            "ingress": [
                {
                    "hostname": "'"$hostname"'",
                    "service": "http://127.0.0.1:'"$local_port"'",
                    "originRequest": {
                        "http2Origin": true,
                        "noTLSVerify": true
                    }
                },
                {
                    "service": "http_status:404"
                }
            ]
        }
    }'

    local response=$(curl -s --max-time 30 -X PUT "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d "$config_json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        analyze_api_error "$response" "更新隧道配置"
        return 1
    fi

    return 0
}

# 检查 DNS 记录是否存在
check_dns_record() {
    local api_token=$1
    local zone_id=$2
    local hostname=$3

    local api_url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$hostname&type=CNAME"
    local response=$(curl -s --max-time 30 -X GET "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        return 1
    fi

    # 提取 record_id (从result数组中提取第一个记录)
    local record_id=$(echo "$response" | grep -o '"result":\[[^\]]*\]' | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -n "$record_id" ] && [ "$record_id" != "null" ]; then
        echo "$record_id"
        return 0
    fi

    return 1
}

# 创建 DNS CNAME 记录
create_dns_record() {
    local api_token=$1
    local zone_id=$2
    local hostname=$3
    local tunnel_id=$4

    print_info "正在创建 DNS 记录: $hostname"

    local api_url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records"
    local response=$(curl -s --max-time 30 -X POST "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "CNAME",
            "name": "'"$hostname"'",
            "content": "'"$tunnel_id"'.cfargotunnel.com",
            "ttl": 120,
            "proxied": true
        }' 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        analyze_api_error "$response" "创建 DNS 记录"
        return 1
    fi

    # 提取 record_id (从result字段中提取)
    local result=$(echo "$response" | grep -o '"result":{[^}]*}' | sed 's/"result"://')
    local record_id=$(echo "$result" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$record_id" ]; then
        echo "$record_id"
        return 0
    else
        print_error "无法提取 DNS 记录 ID"
        return 1
    fi
}

# 删除 DNS 记录
delete_dns_record() {
    local api_token=$1
    local zone_id=$2
    local record_id=$3

    print_info "正在删除 DNS 记录: $record_id"

    local api_url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id"
    local response=$(curl -s --max-time 30 -X DELETE "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        print_warning "DNS 记录删除失败（可能已不存在）"
        local errors=$(echo "$response" | grep -o '"message":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$errors" ]; then
            print_warning "错误信息: $errors"
        fi
        return 1
    fi

    return 0
}

# 删除 Cloudflare Tunnel
delete_cloudflare_tunnel() {
    local api_token=$1
    local account_id=$2
    local tunnel_id=$3

    print_info "正在删除隧道: $tunnel_id"

    local api_url="https://api.cloudflare.com/client/v4/accounts/$account_id/tunnels/$tunnel_id"
    local response=$(curl -s --max-time 30 -X DELETE "$api_url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" 2>/dev/null)

    # 检查 API 响应
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$success" != "true" ]; then
        print_warning "隧道删除失败（可能已不存在）"
        local errors=$(echo "$response" | grep -o '"message":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$errors" ]; then
            print_warning "错误信息: $errors"
        fi
        return 1
    fi

    return 0
}

# 保存隧道信息
save_tunnel_info() {
    local tunnel_id=$1
    local hostname=$2
    local dns_record_id=$3
    local local_port=$4
    local tunnel_name=$5

    cat > .tunnel_info << EOF
tunnel_id=$tunnel_id
hostname=$hostname
dns_record_id=$dns_record_id
local_port=$local_port
tunnel_name=$tunnel_name
EOF

    print_success "隧道信息已保存到 .tunnel_info"
    return 0
}

# 读取隧道信息
load_tunnel_info() {
    if [ -f .tunnel_info ]; then
        source .tunnel_info
        return 0
    else
        return 1
    fi
}

# 加载 .env 文件
load_env_file() {
    local env_file=".env"

    # 检查 .env 文件是否存在
    if [ ! -f "$env_file" ]; then
        print_error "未找到 .env 文件"
        return 1
    fi

    # 检查 .env 文件是否可读
    if [ ! -r "$env_file" ]; then
        print_error ".env 文件不可读"
        return 1
    fi

    # 加载环境变量
    print_info "正在加载环境变量: $env_file"
    source "$env_file"

    if [ $? -eq 0 ]; then
        print_success "环境变量加载成功"
        return 0
    else
        print_error "环境变量加载失败"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
suoha x-tunnel - 快速隧道管理脚本

使用方式:
    交互模式: $(basename $0)
    命令模式: $(basename $0) <command> [options]

命令:
    install  - 安装并启动服务
    stop     - 停止所有服务
    remove   - 卸载并清理所有文件
    status   - 查看服务状态

install 命令选项:
    -o <0|1>  是否启用 opera 前置代理 (0:不启用[默认], 1:启用)
    -c <4|6>  cloudflared 连接模式 (4:IPv4[默认], 6:IPv6)
    -x <token> x-tunnel 身份令牌 (可选)
    -g <code>  opera 国家代码 (AM/AS/EU，默认AM)
    -t <token> Cloudflare 固定隧道令牌 (可选)
    -p <port>  x-tunnel 监听端口 (可选，默认56789)
    -a <token> Cloudflare API 令牌 (可选，用于 API 自动创建或查询固定隧道域名)
    -z <id>    Cloudflare Zone ID (可选，用于 API 自动创建或查询固定隧道域名)
    -d <domain> 隧道域名 (必需，用于 API 自动创建模式)
    -n <name>  隧道名称 (可选，用于 API 自动创建模式，默认: x-tunnel-auto)
    -e        从 .env 文件加载环境变量 (可选，需在项目根目录下创建 .env 文件)

remove 命令选项:
    -a <token> Cloudflare API 令牌 (可选，用于清理 API 创建的隧道)
    -z <id>    Cloudflare Zone ID (可选，用于清理 API 创建的隧道)

模式说明:
    1. Quick Tunnel 模式 (默认):
       使用 Cloudflare Argo Quick Tunnel 自动创建临时隧道
       不需要任何额外参数，隧道域名随机生成
       重启后失效，需要重新创建

    2. API 自动创建模式:
       使用 Cloudflare API 自动创建和管理隧道
       需要: -a, -z, -d 参数
       支持: -n, -o, -c, -x, -p, -g 参数
       隧道信息保存在 .tunnel_info 文件中
       卸载时需要提供 -a 和 -z 参数清理远程资源

    3. 固定隧道模式:
       使用预先在 Cloudflare 后台创建的固定隧道
       需要: -t 参数
       可选: -a, -z 参数用于查询隧道域名
       支持: -o, -c, -x, -p, -g 参数

示例:
    # Quick Tunnel 模式
    $(basename $0) install -o 0 -c 4 -x mytoken
    $(basename $0) install -o 1 -c 4 -g AM

    # 固定隧道模式
    $(basename $0) install -t "CF_Tunnel_Token" -p 56789 -o 0 -c 4 -x mytoken
    $(basename $0) install -t "CF_Tunnel_Token" -a "CF_API_Token" -z "ZONE_ID" -p 56789 -o 0 -c 4

    # API 自动创建模式
    $(basename $0) install -a "YOUR_API_TOKEN" -z "YOUR_ZONE_ID" -d "tunnel.example.com" -o 0 -c 4 -x mytoken
    $(basename $0) install -a "API_TOKEN" -z "ZONE_ID" -d "tunnel.example.com" -n "my-tunnel" -o 1 -g AM -c 4

    # 使用 .env 文件加载环境变量
    $(basename $0) install -e

    # .env 文件示例内容:
    # cf_api_token="YOUR_API_TOKEN"
    # cf_zone_id="YOUR_ZONE_ID"
    # cf_domain="tunnel.example.com"
    # cf_tunnel_name="my-tunnel"
    # opera="0"
    # ips="4"
    # token="your_xtunnel_token"
    # country="AM"
    # port="56789"

    # 服务管理
    $(basename $0) stop
    $(basename $0) remove -a "API_TOKEN" -z "ZONE_ID"
    $(basename $0) status

EOF
}

# 系统检测和依赖安装
setup_environment() {
    linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
    linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
    linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
    n=0
    
    for i in `echo ${linux_os[@]}`
    do
        if [ $i == $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') ]
        then
            break
        else
            n=$[$n+1]
        fi
    done
    
    if [ $n == 5 ]
    then
        print_warning "当前系统 $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2) 没有适配"
        print_info "默认使用 APT 包管理器"
        n=0
    fi
    
    if [ -z $(type -P screen) ]
    then
        print_info "正在安装 screen..."
        ${linux_update[$n]}
        ${linux_install[$n]} screen
        if [ $? -eq 0 ]; then
            print_success "screen 安装成功"
        else
            print_error "screen 安装失败"
            exit 1
        fi
    fi
    
    if [ -z $(type -P curl) ]
    then
        print_info "正在安装 curl..."
        ${linux_update[$n]}
        ${linux_install[$n]} curl
        if [ $? -eq 0 ]; then
            print_success "curl 安装成功"
        else
            print_error "curl 安装失败"
            exit 1
        fi
    fi
}

# 获取可用端口
get_free_port() {
    while true; do
        PORT=$((RANDOM + 1024))
        if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
            echo $PORT
            return
        fi
    done
}

# 验证端口有效性
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "端口号必须是数字"
        return 1
    fi
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        print_error "端口号必须在 1024-65535 之间"
        return 1
    fi
    if lsof -i TCP:$port >/dev/null 2>&1; then
        print_error "端口 $port 已被占用"
        return 1
    fi
    return 0
}

# 等待 screen 会话退出
wait_for_session() {
    local session_name=$1
    local max_wait=30
    local count=0
    
    while [ $count -lt $max_wait ]; do
        screen -S $session_name -X quit 2>/dev/null
        if [ $(screen -ls 2>/dev/null | grep -c "$session_name") -eq 0 ]; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    print_warning "等待 $session_name 退出超时"
    return 1
}

# 停止所有服务
stop_all_services() {
    print_info "正在停止所有服务..."
    
    screen -wipe >/dev/null 2>&1
    
    wait_for_session "x-tunnel"
    wait_for_session "opera"
    wait_for_session "argo"
    
    print_success "所有服务已停止"
}

# 查看服务状态
show_status() {
    echo -e "\n========== 服务状态 =========="
    
    local services=("x-tunnel" "opera" "argo")
    local running_count=0
    
    for service in "${services[@]}"; do
        if screen -ls 2>/dev/null | grep -q "$service"; then
            print_success "$service 服务正在运行"
            running_count=$((running_count + 1))
        else
            print_error "$service 服务未运行"
        fi
    done
    
    echo -e "\n========== 文件检查 =========="
    
    local files=("cloudflared-linux" "x-tunnel-linux" "opera-linux")
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            print_success "$file 存在"
        else
            print_error "$file 不存在"
        fi
    done
    
    echo ""
    
    if [ $running_count -eq 3 ]; then
        print_success "所有服务正常运行"
        return 0
    elif [ $running_count -gt 0 ]; then
        print_warning "部分服务正在运行"
        return 1
    else
        print_error "没有服务在运行"
        return 2
    fi
}

# 快速隧道功能
quicktunnel() {
    print_info "正在检测系统架构..."
    
    case "$(uname -m)" in
        x86_64 | x64 | amd64 )
            if [ ! -f "x-tunnel-linux" ]
            then
                print_info "正在下载 x-tunnel (amd64)..."
                curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-amd64 -o x-tunnel-linux
            fi
            if [ ! -f "opera-linux" ]
            then
                print_info "正在下载 opera-proxy (amd64)..."
                curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-amd64 -o opera-linux
            fi
            if [ ! -f "cloudflared-linux" ]
            then
                print_info "正在下载 cloudflared (amd64)..."
                curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
            fi
            ;;
        i386 | i686 )
            if [ ! -f "x-tunnel-linux" ]
            then
                print_info "正在下载 x-tunnel (386)..."
                curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-386 -o x-tunnel-linux
            fi
            if [ ! -f "opera-linux" ]
            then
                print_info "正在下载 opera-proxy (386)..."
                curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-386 -o opera-linux
            fi
            if [ ! -f "cloudflared-linux" ]
            then
                print_info "正在下载 cloudflared (386)..."
                curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
            fi
            ;;
        armv8 | arm64 | aarch64 )
            if [ ! -f "x-tunnel-linux" ]
            then
                print_info "正在下载 x-tunnel (arm64)..."
                curl -L https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-arm64 -o x-tunnel-linux
            fi
            if [ ! -f "opera-linux" ]
            then
                print_info "正在下载 opera-proxy (arm64)..."
                curl -L https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-arm64 -o opera-linux
            fi
            if [ ! -f "cloudflared-linux" ]
            then
                print_info "正在下载 cloudflared (arm64)..."
                curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
            fi
            ;;
        * )
            print_error "当前架构 $(uname -m) 没有适配"
            exit 1
            ;;
    esac
    
    chmod +x cloudflared-linux x-tunnel-linux opera-linux
    print_success "二进制文件下载完成"
    
    if [ "$opera" = "1" ]
    then
        operaport=$(get_free_port)
        print_info "正在启动 Opera 代理 (国家: $country, 端口: $operaport)..."
        screen -dmUS opera ./opera-linux -country $country -socks-mode -bind-address "127.0.0.1:$operaport"
    fi
    
    sleep 1
    
    # 端口分配逻辑
    if [ -n "$port" ]; then
        wsport=$port
        print_info "使用固定端口: $wsport"
    else
        wsport=$(get_free_port)
        print_info "使用随机端口: $wsport"
    fi
    
    if [ -z "$token" ]
    then
        if [ "$opera" = "1" ]
        then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport
        fi
    else
        if [ "$opera" = "1" ]
        then
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $token -f socks5://127.0.0.1:$operaport
        else
            screen -dmUS x-tunnel ./x-tunnel-linux -l ws://127.0.0.1:$wsport -token $token
        fi
    fi
    
    # Cloudflare 隧道启动逻辑
    # 优先级: API 自动创建 > 固定隧道 > Quick Tunnel
    if [ -n "$cf_api_token" ] && [ -n "$cf_zone_id" ] && [ -n "$cf_domain" ]; then
        # API 自动创建模式
        print_info "使用 Cloudflare API 自动创建隧道..."

        # 设置默认隧道名称
        if [ -z "$cf_tunnel_name" ]; then
            cf_tunnel_name="x-tunnel-auto"
        fi

        # 1. 获取 Account ID
        ACCOUNT_ID=$(get_account_id "$cf_api_token")
        if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
            print_error "无法获取 Account ID，请检查 API Token"
            exit 1
        fi
        print_success "Account ID: $ACCOUNT_ID"

        # 2. 创建或复用隧道
        print_info "正在准备隧道: $cf_tunnel_name"
        TUNNEL_INFO=$(create_cloudflare_tunnel "$cf_api_token" "$ACCOUNT_ID" "$cf_tunnel_name" "true")
        if [ $? -ne 0 ]; then
            print_error "隧道操作失败"
            exit 1
        fi

        TUNNEL_ID=$(echo "$TUNNEL_INFO" | cut -d'|' -f1)
        TUNNEL_TOKEN=$(echo "$TUNNEL_INFO" | cut -d'|' -f2)
        CREDENTIALS_FILE=$(echo "$TUNNEL_INFO" | cut -d'|' -f3)

        if [ -z "$TUNNEL_ID" ] || [ -z "$TUNNEL_TOKEN" ]; then
            print_error "隧道操作失败，无法提取 tunnel_id 或 tunnel_token"
            exit 1
        fi
        print_success "隧道准备成功: $TUNNEL_ID"

        # 3. 更新隧道配置
        print_info "正在配置隧道 ingress..."
        update_tunnel_config "$cf_api_token" "$ACCOUNT_ID" "$TUNNEL_ID" "$cf_domain" "$wsport"
        if [ $? -ne 0 ]; then
            print_error "隧道配置失败"
            exit 1
        fi
        print_success "隧道配置成功"

        # 4. 检查并创建 DNS 记录
        print_info "正在检查 DNS 记录: $cf_domain"
        EXISTING_RECORD_ID=$(check_dns_record "$cf_api_token" "$cf_zone_id" "$cf_domain")
        if [ $? -eq 0 ] && [ -n "$EXISTING_RECORD_ID" ]; then
            print_warning "DNS 记录已存在 (ID: $EXISTING_RECORD_ID)，将尝试更新"
            DNS_RECORD_ID=$EXISTING_RECORD_ID
        else
            print_info "正在创建 DNS 记录: $cf_domain"
            DNS_RECORD_ID=$(create_dns_record "$cf_api_token" "$cf_zone_id" "$cf_domain" "$TUNNEL_ID")
            if [ $? -ne 0 ]; then
                print_error "DNS 记录创建失败"
                exit 1
            fi
        fi
        print_success "DNS 记录配置成功"

        # 5. 保存隧道信息
        save_tunnel_info "$TUNNEL_ID" "$cf_domain" "$DNS_RECORD_ID" "$wsport" "$cf_tunnel_name"

        # 6. 启动 cloudflared
        print_info "正在更新 cloudflared..."
        ./cloudflared-linux update

        print_info "正在启动 cloudflared..."
        screen -dmUS argo ./cloudflared-linux tunnel run --token $TUNNEL_TOKEN

        # 设置域名变量用于后续显示
        DOMAIN="$cf_domain"
        API_MODE=true

    elif [ -n "$tunnel_token" ]; then
        # 固定隧道模式
        print_info "正在更新 cloudflared..."
        ./cloudflared-linux update

        print_info "使用固定 Cloudflare 隧道..."
        screen -dmUS argo ./cloudflared-linux tunnel run --token $tunnel_token

        # 尝试从 API 获取固定隧道域名
        if [ -n "$cf_api_token" ] && [ -n "$cf_zone_id" ]; then
            DOMAIN=$(get_tunnel_domain_from_api "$tunnel_token" "$cf_api_token" "$cf_zone_id")
            if [ $? -eq 0 ]; then
                print_success "成功获取隧道域名: $DOMAIN"
            else
                DOMAIN="已配置的固定隧道 (域名查询失败)"
            fi
        else
            print_info "如需显示隧道域名，请提供 Cloudflare API Token 和 Zone ID"
            DOMAIN="已配置的固定隧道"
        fi
        API_MODE=false
    else
        # Quick Tunnel 模式
        metricsport=$(get_free_port)

        print_info "正在更新 cloudflared..."
        ./cloudflared-linux update

        print_info "使用 Cloudflare Quick Tunnel..."
        screen -dmUS argo ./cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --url 127.0.0.1:$wsport --metrics 0.0.0.0:$metricsport

        print_info "正在获取隧道域名..."
        while true; do
            RESP=$(curl -s --max-time 5 "http://127.0.0.1:$metricsport/metrics" 2>/dev/null)

            if echo "$RESP" | grep -q 'userHostname='; then
                DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                break
            else
                echo -n "."
                sleep 1
            fi
        done
        API_MODE=false
    fi
    
    clear
    echo ""
    print_success "隧道创建成功！"
    echo ""
    echo "========================================"
    if [ "$API_MODE" = true ]; then
        echo "模式: API 自动创建隧道"
        echo "隧道域名: $DOMAIN"
        echo "x-tunnel 监听端口: $wsport"
        echo "Tunnel ID: $TUNNEL_ID"
        if [ -z "$token" ]
        then
            echo "未设置 x-tunnel token"
        else
            echo "x-tunnel 身份令牌: $token"
        fi
        print_info "隧道信息已保存到 .tunnel_info，使用 './suoha-x.sh remove' 清理"
    elif [ -n "$tunnel_token" ]; then
        echo "模式: 固定 Cloudflare 隧道"
        echo "隧道域名: $DOMAIN"
        echo "x-tunnel 监听端口: $wsport"
        print_info "注意：固定隧道的域名需要在 Cloudflare 后台查看"
        if [ -z "$token" ]
        then
            echo "未设置 x-tunnel token"
        else
            echo "x-tunnel 身份令牌: $token"
        fi
    else
        if [ -z "$token" ]
        then
            echo "未设置 x-tunnel token, 链接为: $DOMAIN:443"
        else
            echo "已设置 x-tunnel token, 链接为: $DOMAIN:443"
            echo "x-tunnel 身份令牌: $token"
        fi
    fi
    echo "========================================"
    echo ""
    print_info "使用 './suoha-x.sh status' 查看服务状态"
    echo ""
}

# 安装服务
install_service() {
    print_info "开始安装服务..."
    setup_environment
    
    # 停止现有服务
    stop_all_services
    
    # 验证参数
    if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
        print_error "无效的 opera 参数，必须是 0 或 1"
        exit 1
    fi
    
    if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
        print_error "无效的 cloudflared 连接模式，必须是 4 或 6"
        exit 1
    fi
    
    # 验证固定端口
    if [ -n "$port" ]; then
        if ! validate_port "$port"; then
            exit 1
        fi
        print_info "固定端口: $port"
    fi
    
    # 验证隧道令牌
    if [ -n "$tunnel_token" ]; then
        print_info "Cloudflare 固定隧道: 已启用 (${tunnel_token:0:15}...)"
    fi
    
    if [ "$opera" = "1" ]; then
        if [ -z "$country" ]; then
            country="AM"
        fi
        country=${country^^}
        if [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ]; then
            print_error "无效的 opera 国家代码，必须是 AM、AS 或 EU"
            exit 1
        fi
        print_info "Opera 前置代理: 启用 (国家: $country)"
    else
        print_info "Opera 前置代理: 禁用"
    fi
    
    print_info "Cloudflare 连接模式: IPv$ips"
    
    if [ -n "$token" ]; then
        print_info "x-tunnel token: 已设置"
    else
        print_info "x-tunnel token: 未设置"
    fi
    
    echo ""
    sleep 1
    quicktunnel
}

# 卸载清理
remove_all() {
    print_info "正在卸载并清理所有文件..."

    # 停止所有服务
    stop_all_services

    # 检查并清理 API 创建的隧道
    if [ -f .tunnel_info ]; then
        print_info "检测到 API 创建的隧道，正在清理..."

        # 加载隧道信息
        if ! load_tunnel_info; then
            print_warning "无法加载隧道信息，跳过远程资源清理"
            read -p "是否继续清理本地文件? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                print_info "取消清理"
                exit 0
            fi
        fi

        # 检查是否有必要的清理参数
        if [ -z "$cf_api_token" ] || [ -z "$cf_zone_id" ]; then
            print_warning "请提供 Cloudflare API Token 和 Zone ID 以清理远程资源"
            print_info "使用方式: ./suoha-x.sh remove -a API_TOKEN -z ZONE_ID"
            read -p "是否继续清理本地文件? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                print_info "取消清理"
                exit 0
            fi
        else
            # 删除 DNS 记录
            if [ -n "$dns_record_id" ]; then
                print_info "正在删除 DNS 记录..."
                delete_dns_record "$cf_api_token" "$cf_zone_id" "$dns_record_id"
                print_success "DNS 记录已删除"
            fi

            # 删除隧道
            if [ -n "$tunnel_id" ]; then
                print_info "正在删除隧道: $tunnel_id"
                ACCOUNT_ID=$(get_account_id "$cf_api_token")
                if [ $? -eq 0 ] && [ -n "$ACCOUNT_ID" ]; then
                    delete_cloudflare_tunnel "$cf_api_token" "$ACCOUNT_ID" "$tunnel_id"
                    print_success "隧道已删除"
                else
                    print_warning "无法获取 Account ID，跳过隧道删除"
                fi
            fi

            # 删除 credentials 文件
            if [ -f "/tmp/tunnel-$tunnel_id.json" ]; then
                rm -f "/tmp/tunnel-$tunnel_id.json"
                print_success "credentials 文件已删除"
            fi
        fi

        # 删除隧道信息文件
        rm -f .tunnel_info
        print_success "隧道信息已删除"
    fi

    # 删除二进制文件
    rm -rf cloudflared-linux x-tunnel-linux opera-linux

    if [ $? -eq 0 ]; then
        print_success "清理完成"
    else
        print_error "清理失败"
        exit 1
    fi
}

# 交互式菜单
interactive_mode() {
    clear
    echo "========================================"
    echo "       suoha x-tunnel 管理脚本"
    echo "========================================"
    echo ""
    echo "梭哈模式不需要自己提供域名，使用 CF ARGO QUICK TUNNEL 创建快速链接"
    echo "梭哈模式在重启或者脚本再次运行后失效，如果需要使用需要再次运行创建"
    echo ""
    echo "========================================"
    echo ""
    echo -e "\033[0;32m梭哈是一种智慧!!! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈...\033[0m"
    echo ""
    echo "1. 梭哈模式 (Quick Tunnel)"
    echo "2. API 自动创建模式 (需要 API Token 和域名)"
    echo "3. 固定隧道模式 (需要 Tunnel Token)"
    echo "4. 停止服务"
    echo "5. 清空缓存 (卸载)"
    echo "6. 查看状态"
    echo "0. 退出脚本"
    echo ""
    read -p "请选择模式 (默认1): " mode
    
    if [ -z "$mode" ]; then
        mode=1
    fi
    
    case $mode in
        1)
            # Quick Tunnel 模式
            echo ""
            echo "========================================"
            echo "       Quick Tunnel 模式"
            echo "========================================"
            echo ""

            read -p "是否启用 opera 前置代理 (0.不启用[默认], 1.启用): " opera
            if [ -z "$opera" ]; then
                opera=0
            fi

            if [ "$opera" = "1" ]; then
                echo ""
                echo "注意: opera 前置代理仅支持 AM, AS, EU 地区"
                echo "  AM: 北美地区"
                echo "  AS: 亚太地区"
                echo "  EU: 欧洲地区"
                echo ""
                read -p "请输入 opera 前置代理的国家代码 (默认AM): " country
                if [ -z "$country" ]; then
                    country=AM
                fi
                country=${country^^}
                if [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ]; then
                    print_error "请输入正确的 opera 前置代理国家代码"
                    exit 1
                fi
            fi

            if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
                print_error "请输入正确的 opera 前置代理模式"
                exit 1
            fi

            read -p "请选择 cloudflared 连接模式 IPV4 或者 IPV6 (输入4或6, 默认4): " ips
            if [ -z "$ips" ]; then
                ips=4
            fi
            if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
                print_error "请输入正确的 cloudflared 连接模式"
                exit 1
            fi

            # 固定端口设置
            read -p "是否使用固定端口 (0.否[默认], 1.是): " use_fixed_port
            if [ -z "$use_fixed_port" ]; then
                use_fixed_port=0
            fi
            if [ "$use_fixed_port" = "1" ]; then
                read -p "请输入端口号 (1024-65535, 默认56789): " port_input
                if [ -z "$port_input" ]; then
                    port_input=56789
                fi
                if ! validate_port "$port_input"; then
                    exit 1
                fi
                port=$port_input
            fi

            read -p "请设置 x-tunnel 的 token (可留空): " token

            setup_environment
            stop_all_services
            clear
            sleep 1
            quicktunnel
            ;;
        2)
            # API 自动创建模式
            echo ""
            echo "========================================"
            echo "       API 自动创建模式"
            echo "========================================"
            echo ""

            read -p "请输入 Cloudflare API Token: " cf_api_token
            if [ -z "$cf_api_token" ]; then
                print_error "API Token 不能为空"
                exit 1
            fi

            read -p "请输入 Zone ID: " cf_zone_id
            if [ -z "$cf_zone_id" ]; then
                print_error "Zone ID 不能为空"
                exit 1
            fi

            read -p "请输入隧道域名 (例如: tunnel.example.com): " cf_domain
            if [ -z "$cf_domain" ]; then
                print_error "隧道域名不能为空"
                exit 1
            fi

            read -p "请输入隧道名称 (默认: x-tunnel-auto): " cf_tunnel_name
            if [ -z "$cf_tunnel_name" ]; then
                cf_tunnel_name="x-tunnel-auto"
            fi

            read -p "是否启用 opera 前置代理 (0.不启用[默认], 1.启用): " opera
            if [ -z "$opera" ]; then
                opera=0
            fi

            if [ "$opera" = "1" ]; then
                echo ""
                echo "注意: opera 前置代理仅支持 AM, AS, EU 地区"
                echo "  AM: 北美地区"
                echo "  AS: 亚太地区"
                echo "  EU: 欧洲地区"
                echo ""
                read -p "请输入 opera 前置代理的国家代码 (默认AM): " country
                if [ -z "$country" ]; then
                    country=AM
                fi
                country=${country^^}
                if [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ]; then
                    print_error "请输入正确的 opera 前置代理国家代码"
                    exit 1
                fi
            fi

            if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
                print_error "请输入正确的 opera 前置代理模式"
                exit 1
            fi

            read -p "请选择 cloudflared 连接模式 IPV4 或者 IPV6 (输入4或6, 默认4): " ips
            if [ -z "$ips" ]; then
                ips=4
            fi
            if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
                print_error "请输入正确的 cloudflared 连接模式"
                exit 1
            fi

            # 固定端口设置
            read -p "是否使用固定端口 (0.否[默认], 1.是): " use_fixed_port
            if [ -z "$use_fixed_port" ]; then
                use_fixed_port=0
            fi
            if [ "$use_fixed_port" = "1" ]; then
                read -p "请输入端口号 (1024-65535, 默认56789): " port_input
                if [ -z "$port_input" ]; then
                    port_input=56789
                fi
                if ! validate_port "$port_input"; then
                    exit 1
                fi
                port=$port_input
            fi

            read -p "请设置 x-tunnel 的 token (可留空): " token

            setup_environment
            stop_all_services
            clear
            sleep 1
            quicktunnel
            ;;
        3)
            # 固定隧道模式
            echo ""
            echo "========================================"
            echo "       固定隧道模式"
            echo "========================================"
            echo ""

            read -p "请输入 Cloudflare 隧道令牌: " tunnel_token
            if [ -z "$tunnel_token" ]; then
                print_error "固定隧道模式需要提供隧道令牌"
                exit 1
            fi

            # 询问是否提供 API Token 和 Zone ID
            read -p "是否提供 Cloudflare API Token 和 Zone ID 来查询隧道域名? (0.否[默认], 1.是): " use_api
            if [ -z "$use_api" ]; then
                use_api=0
            fi
            if [ "$use_api" = "1" ]; then
                read -p "请输入 Cloudflare API Token: " cf_api_token
                if [ -z "$cf_api_token" ]; then
                    print_error "API Token 不能为空"
                    exit 1
                fi

                read -p "请输入 Zone ID: " cf_zone_id
                if [ -z "$cf_zone_id" ]; then
                    print_error "Zone ID 不能为空"
                    exit 1
                fi
            fi

            read -p "是否启用 opera 前置代理 (0.不启用[默认], 1.启用): " opera
            if [ -z "$opera" ]; then
                opera=0
            fi

            if [ "$opera" = "1" ]; then
                echo ""
                echo "注意: opera 前置代理仅支持 AM, AS, EU 地区"
                echo "  AM: 北美地区"
                echo "  AS: 亚太地区"
                echo "  EU: 欧洲地区"
                echo ""
                read -p "请输入 opera 前置代理的国家代码 (默认AM): " country
                if [ -z "$country" ]; then
                    country=AM
                fi
                country=${country^^}
                if [ "$country" != "AM" ] && [ "$country" != "AS" ] && [ "$country" != "EU" ]; then
                    print_error "请输入正确的 opera 前置代理国家代码"
                    exit 1
                fi
            fi

            if [ "$opera" != "0" ] && [ "$opera" != "1" ]; then
                print_error "请输入正确的 opera 前置代理模式"
                exit 1
            fi

            read -p "请选择 cloudflared 连接模式 IPV4 或者 IPV6 (输入4或6, 默认4): " ips
            if [ -z "$ips" ]; then
                ips=4
            fi
            if [ "$ips" != "4" ] && [ "$ips" != "6" ]; then
                print_error "请输入正确的 cloudflared 连接模式"
                exit 1
            fi

            # 固定端口设置
            read -p "是否使用固定端口 (0.否[默认], 1.是): " use_fixed_port
            if [ -z "$use_fixed_port" ]; then
                use_fixed_port=0
            fi
            if [ "$use_fixed_port" = "1" ]; then
                read -p "请输入端口号 (1024-65535, 默认56789): " port_input
                if [ -z "$port_input" ]; then
                    port_input=56789
                fi
                if ! validate_port "$port_input"; then
                    exit 1
                fi
                port=$port_input
            fi

            read -p "请设置 x-tunnel 的 token (可留空): " token

            setup_environment
            stop_all_services
            clear
            sleep 1
            quicktunnel
            ;;
        4)
            stop_all_services
            clear
            print_success "服务已停止"
            ;;
        5)
            remove_all
            clear
            print_success "清理完成"
            ;;
        6)
            show_status
            ;;
        0)
            echo ""
            print_success "退出成功"
            exit 0
            ;;
        *)
            print_error "无效的选择"
            exit 1
            ;;
    esac
}

# 参数解析
parse_arguments() {
    local command=$1
    shift
    
    case $command in
        install)
            while getopts "o:c:x:g:t:p:a:z:d:n:eh" opt; do
                case $opt in
                    o)
                        opera=$OPTARG
                        ;;
                    c)
                        ips=$OPTARG
                        ;;
                    x)
                        token=$OPTARG
                        ;;
                    g)
                        country=$OPTARG
                        ;;
                    t)
                        tunnel_token=$OPTARG
                        ;;
                    p)
                        port=$OPTARG
                        ;;
                    a)
                        cf_api_token=$OPTARG
                        ;;
                    z)
                        cf_zone_id=$OPTARG
                        ;;
                    d)
                        cf_domain=$OPTARG
                        ;;
                    n)
                        cf_tunnel_name=$OPTARG
                        ;;
                    e)
                        load_env_file
                        if [ $? -ne 0 ]; then
                            exit 1
                        fi
                        ;;
                    h)
                        show_help
                        exit 0
                        ;;
                    \?)
                        print_error "无效的参数: -$OPTARG"
                        show_help
                        exit 1
                        ;;
                    :)
                        print_error "选项 -$OPTARG 需要参数"
                        show_help
                        exit 1
                        ;;
                esac
            done

            install_service
            ;;
        stop)
            stop_all_services
            ;;
        remove)
            # 处理 remove 命令的参数（用于清理 API 创建的资源）
            shift  # 移除 "remove" 命令
            while getopts "a:z:h" opt; do
                case $opt in
                    a)
                        cf_api_token=$OPTARG
                        ;;
                    z)
                        cf_zone_id=$OPTARG
                        ;;
                    h)
                        show_help
                        exit 0
                        ;;
                    \?)
                        print_error "无效的参数: -$OPTARG"
                        show_help
                        exit 1
                        ;;
                    :)
                        print_error "选项 -$OPTARG 需要参数"
                        show_help
                        exit 1
                        ;;
                esac
            done
            remove_all
            ;;
        status)
            show_status
            ;;
        ""|"-h"|"--help")
            show_help
            exit 0
            ;;
        *)
            print_error "未知的命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 默认值
opera="0"
ips="4"
token=""
country=""
tunnel_token=""
port="56789"
cf_api_token=""
cf_zone_id=""
cf_domain=""
cf_tunnel_name=""

# 主函数
main() {
    if [ $# -eq 0 ]; then
        interactive_mode
    else
        parse_arguments "$@"
    fi
}

# 执行主函数
main "$@"
