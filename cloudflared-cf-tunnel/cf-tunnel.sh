#!/usr/bin/env bash
# Cloudflare Tunnel 简化配置脚本
# 用途：将本地指定端口通过Cloudflare Tunnel绑定到域名

set -euo pipefail

TUNNEL_PID_FILE=".tunnel_pid"
TUNNEL_LOCK_FILE="/tmp/cf-tunnel.lock"

print_success(){ echo -e "\033[0;32m✓ $*\033[0m"; }
print_error(){ echo -e "\033[0;31m✗ $*\033[0m"; }
print_info(){ echo -e "\033[0;36mℹ $*\033[0m"; }
print_warning(){ echo -e "\033[0;33m⚠ $*\033[0m"; }

cf_api() {
  local method="$1" url="$2" data="${3:-}"
  local response
  if [ -n "$data" ]; then
    response=$(curl -sS --max-time 30 -X "$method" "$url" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_GLOBAL_KEY" \
      -H "Content-Type: application/json" \
      -d "$data" 2>&1)
  else
    response=$(curl -sS --max-time 30 -X "$method" "$url" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_GLOBAL_KEY" \
      -H "Content-Type: application/json" 2>&1)
  fi

  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    print_error "API 请求失败 (curl 错误: $exit_code)"
    return 1
  fi

  echo "$response"
}

json_get() {
  local json="$1" jq_expr="$2" fallback_regex="$3"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r "$jq_expr" 2>/dev/null
  else
    echo "$json" | sed -nE "s/.*$fallback_regex.*/\\1/p" | head -n 1
  fi
}

get_zone_id() {
  local domain="$1"
  local parts len
  IFS='.' read -ra parts <<< "$domain"
  len=${#parts[@]}

  local candidates=()
  for ((i=2; i<=len; i++)); do
    local d=""
    for ((j=len-i; j<len; j++)); do
      [ -z "$d" ] && d="${parts[$j]}" || d="$d.${parts[$j]}"
    done
    candidates+=("$d")
  done

  local uniq=() seen=$'\n' c
  for c in "${candidates[@]}"; do
    if [[ "$seen" != *$'\n'"$c"$'\n'* ]]; then
      uniq+=("$c"); seen+="$c"$'\n'
    fi
  done

  for root in "${uniq[@]}"; do
    local response success count zone_id
    response=$(cf_api GET "https://api.cloudflare.com/client/v4/zones?name=$root")
    [ -z "$response" ] && continue
    success=$(json_get "$response" '.success // empty' '"success":(true|false)')
    [ "$success" != "true" ] && continue
    count=$(json_get "$response" '.result_info.total_count // 0' '"total_count":([0-9]+)')
    [ "${count:-0}" = "0" ] && continue
    zone_id=$(json_get "$response" '.result[0].id // empty' '"id":"([a-f0-9-]+)"')
    [ -n "$zone_id" ] && [ "$zone_id" != "null" ] && { echo "$zone_id"; return 0; }
  done
  return 1
}

get_account_id() {
  local resp success
  resp=$(cf_api GET "https://api.cloudflare.com/client/v4/accounts")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

check_tunnel_exists() {
  local account_id="$1" name="$2"
  local resp success count
  resp=$(cf_api GET "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel?name=$name")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  count=$(json_get "$resp" '.result_info.total_count // 0' '"total_count":([0-9]+)')
  [ "${count:-0}" = "0" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

delete_cloudflare_tunnel() {
  local account_id="$1" tunnel_id="$2"
  cf_api DELETE "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id" >/dev/null 2>&1
}

ensure_tunnel_deleted() {
  local account_id="$1" name="$2" max_try="${3:-3}" delay="${4:-5}"
  local attempt=1

  while [ "$attempt" -le "$max_try" ]; do
    local tid
    tid=$(check_tunnel_exists "$account_id" "$name" 2>/dev/null || true)

    if [ -z "$tid" ] || [ "$tid" = "null" ]; then
      return 0
    fi

    print_warning "检测到同名隧道仍存在（ID: $tid），开始第 ${attempt}/${max_try} 次删除..."
    delete_cloudflare_tunnel "$account_id" "$tid"
    sleep "$delay"

    tid=$(check_tunnel_exists "$account_id" "$name" 2>/dev/null || true)
    if [ -z "$tid" ] || [ "$tid" = "null" ]; then
      print_success "隧道删除成功（name=$name）"
      return 0
    fi

    attempt=$((attempt+1))
  done

  print_error "删除失败：隧道（name=$name）在重试 ${max_try} 次后仍存在"
  return 1
}

create_cloudflare_tunnel() {
  local account_id="$1" name="$2"
  local existing
  existing=$(check_tunnel_exists "$account_id" "$name" || true)

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    print_warning "隧道已存在（$existing），先删除再创建"
    ensure_tunnel_deleted "$account_id" "$name" 3 5 || return 1
  fi

  local data resp success
  data=$(printf '{"name":"%s"}' "$name")
  resp=$(cf_api POST "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel" "$data")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1

  local tid ttoken
  tid=$(json_get "$resp" '.result.id // empty' '"id":"([a-f0-9-]+)"')
  ttoken=$(json_get "$resp" '.result.token // empty' '"token":"([^"]+)"')
  [ -z "$tid" ] && return 1

  echo "$tid"
  echo "$ttoken"
}

update_tunnel_config() {
  local account_id="$1" tunnel_id="$2" hostname="$3" local_port="$4"
  local cfg resp success
  cfg=$(cat <<EOF
{
  "config": {
    "ingress": [
      {"hostname": "$hostname", "service": "http://127.0.0.1:$local_port", "originRequest": {"noTLSVerify": true}},
      {"service": "http_status:404"}
    ]
  }
}
EOF
)
  resp=$(cf_api PUT "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id/configurations" "$cfg")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" = "true" ]
}

check_dns_record() {
  local zone_id="$1" hostname="$2"
  local resp success count
  resp=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$hostname&type=CNAME")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  count=$(json_get "$resp" '.result_info.total_count // 0' '"total_count":([0-9]+)')
  [ "${count:-0}" = "0" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

delete_dns_record() {
  local zone_id="$1" rid="$2"
  cf_api DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rid" >/dev/null 2>&1
}

create_dns_record() {
  local zone_id="$1" hostname="$2" tunnel_id="$3"
  local data resp success
  data=$(cat <<EOF
{
  "type": "CNAME",
  "name": "$hostname",
  "content": "$tunnel_id.cfargotunnel.com",
  "ttl": 1,
  "proxied": true,
  "comment": "Managed by cf-tunnel.sh"
}
EOF
)
  resp=$(cf_api POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" "$data")
  [ -z "$resp" ] && return 1
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  json_get "$resp" '.result.id // empty' '"id":"([a-f0-9-]+)"'
}

check_port_available() {
  local port="$1"
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" 2>/dev/null && return 1
  elif command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":$port\s" && return 1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -q ":$port\s" && return 1
  fi
  return 0
}

download_cloudflared() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    i386|i686) arch="386" ;;
    arm64|aarch64) arch="arm64" ;;
    *) print_error "不支持的架构: $arch"; exit 1 ;;
  esac

  if [ ! -f cloudflared ]; then
    print_info "下载 cloudflared..."
    local tmp_file="cloudflared.tmp"
    curl -fL --retry 3 --connect-timeout 10 --max-time 120 \
      -o "$tmp_file" \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch"

    if [ ! -s "$tmp_file" ]; then
      rm -f "$tmp_file"
      print_error "cloudflared 下载失败或文件为空"
      exit 1
    fi

    mv "$tmp_file" cloudflared
    chmod +x cloudflared
    print_success "cloudflared 下载完成"
  fi
}

stop_cloudflared() {
  print_info "停止 cloudflared 服务..."

  local pid=""
  if [ -f "$TUNNEL_PID_FILE" ]; then
    pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)
  fi

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    print_success "服务已停止 (PID: $pid)"
  else
    pkill -f "cloudflared.*tunnel run" 2>/dev/null || true
    print_success "服务已停止"
  fi

  rm -f "$TUNNEL_PID_FILE"
}

show_tunnel_status() {
  if [ ! -f ".tunnel_info" ]; then
    print_warning "未找到隧道配置信息"
    return 1
  fi

  local pid=""
  [ -f "$TUNNEL_PID_FILE" ] && pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)

  echo ""
  echo "========== 隧道信息 =========="
  source .tunnel_info

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    print_success "运行中 (PID: $pid)"
  else
    print_error "未运行"
  fi

  echo "域名: $hostname"
  echo "本地端口: $local_port"
  echo "隧道名称: $tunnel_name"
  echo "Tunnel ID: $tunnel_id"
  echo "========================================="
}

save_tunnel_info() {
  local tunnel_id="$1" hostname="$2" dns_record_id="$3" local_port="$4" tunnel_name="$5" zone_id="$6" account_id="$7" tunnel_token="$8"
  cat > .tunnel_info <<EOF
tunnel_id=$tunnel_id
hostname=$hostname
dns_record_id=$dns_record_id
local_port=$local_port
tunnel_name=$tunnel_name
zone_id=$zone_id
account_id=$account_id
tunnel_token=$tunnel_token
EOF
  chmod 600 .tunnel_info
  print_warning ".tunnel_info 包含敏感信息，请妥善保管"
}

run_tunnel() {
  print_info "配置 Cloudflare Tunnel..."

  [ -n "${CF_EMAIL:-}" ] || { print_error "请提供 CF_EMAIL"; return 1; }
  [ -n "${CF_GLOBAL_KEY:-}" ] || { print_error "请提供 CF_GLOBAL_KEY"; return 1; }
  [ -n "${DOMAIN:-}" ] || { print_error "请提供 DOMAIN"; return 1; }
  [ -n "${TUNNEL_NAME:-}" ] || { print_error "请提供 TUNNEL_NAME"; return 1; }
  [ -n "${LOCAL_PORT:-}" ] || { print_error "请提供 LOCAL_PORT"; return 1; }

  exec 200>"$TUNNEL_LOCK_FILE"
  flock -n 200 || { print_error "脚本已在运行，请先停止现有实例"; exit 1; }

  if check_port_available "$LOCAL_PORT"; then
    print_warning "本地端口 $LOCAL_PORT 未被占用，请确保您的服务已启动"
  fi

  stop_cloudflared
  download_cloudflared

  print_info "正在查询 Zone ID..."
  local ZONE_ID ACCOUNT_ID
  ZONE_ID=$(get_zone_id "$DOMAIN") || { print_error "获取 Zone ID 失败，请确认域名在 Cloudflare 中"; return 1; }
  print_success "Zone ID: $ZONE_ID"

  print_info "正在查询 Account ID..."
  ACCOUNT_ID=$(get_account_id) || { print_error "获取 Account ID 失败"; return 1; }
  print_success "Account ID: $ACCOUNT_ID"

  print_info "创建/重建隧道: $TUNNEL_NAME"
  local TUNNEL_RESULT TUNNEL_ID TUNNEL_TOKEN
  TUNNEL_RESULT=$(create_cloudflare_tunnel "$ACCOUNT_ID" "$TUNNEL_NAME") || { print_error "创建隧道失败"; return 1; }
  TUNNEL_ID=$(echo "$TUNNEL_RESULT" | sed -n '1p')
  TUNNEL_TOKEN=$(echo "$TUNNEL_RESULT" | sed -n '2p')
  print_success "Tunnel ID: $TUNNEL_ID"

  print_info "更新隧道配置: $DOMAIN -> 127.0.0.1:$LOCAL_PORT"
  update_tunnel_config "$ACCOUNT_ID" "$TUNNEL_ID" "$DOMAIN" "$LOCAL_PORT" || print_warning "隧道配置更新失败"

  print_info "配置 DNS 记录..."
  local DNS_RECORD_ID
  DNS_RECORD_ID=$(check_dns_record "$ZONE_ID" "$DOMAIN" 2>/dev/null || true)
  [ -n "$DNS_RECORD_ID" ] && delete_dns_record "$ZONE_ID" "$DNS_RECORD_ID" || true
  DNS_RECORD_ID=$(create_dns_record "$ZONE_ID" "$DOMAIN" "$TUNNEL_ID" || true)
  [ -n "$DNS_RECORD_ID" ] && print_success "DNS 记录已创建" || print_warning "DNS 记录创建失败"

  save_tunnel_info "$TUNNEL_ID" "$DOMAIN" "$DNS_RECORD_ID" "$LOCAL_PORT" "$TUNNEL_NAME" "$ZONE_ID" "$ACCOUNT_ID" "$TUNNEL_TOKEN"

  print_info "启动 cloudflared..."
  ./cloudflared tunnel run --token "$TUNNEL_TOKEN" &
  local pid=$!
  echo "$pid" > "$TUNNEL_PID_FILE"
  sleep 2

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$TUNNEL_PID_FILE"
    print_error "cloudflared 启动失败"
    return 1
  fi

  print_success "========== 隧道已启动 =========="
  echo "域名: $DOMAIN"
  echo "本地端口: $LOCAL_PORT"
  echo "Tunnel ID: $TUNNEL_ID"
  echo "进程 PID: $pid"
  echo ""
  echo "停止服务: ./cf-tunnel.sh stop"
  echo "查看状态: ./cf-tunnel.sh status"
  echo "========================================="
}

show_help() {
cat <<'HLP'
用法:
  方式一（环境变量）:
    export CF_EMAIL="your-email@example.com"
    export CF_GLOBAL_KEY="your-global-api-key"
    export DOMAIN="sub.example.com"
    export TUNNEL_NAME="my-tunnel"
    export LOCAL_PORT="8080"
    ./cf-tunnel.sh run

  方式二（命令行参数）:
    ./cf-tunnel.sh -e "your-email@example.com" \
                    -k "your-global-api-key" \
                    -d "sub.example.com" \
                    -n "my-tunnel" \
                    -p "8080" \
                    -c run

参数说明:
  环境变量:
    CF_EMAIL        Cloudflare 账户邮箱
    CF_GLOBAL_KEY   Cloudflare Global API Key（从 https://dash.cloudflare.com/profile/api-tokens 获取）
    DOMAIN          要绑定的域名（必须在 Cloudflare 中）
    TUNNEL_NAME     隧道名称（重复时自动删除重建）
    LOCAL_PORT      本地监听端口

  命令行参数:
    -e, --email     Cloudflare 账户邮箱（对应 CF_EMAIL）
    -k, --key       Cloudflare Global API Key（对应 CF_GLOBAL_KEY）
    -d, --domain    要绑定的域名（对应 DOMAIN）
    -n, --name      隧道名称（对应 TUNNEL_NAME）
    -p, --port      本地监听端口（对应 LOCAL_PORT）
    -c, --command   执行的命令：run/stop/restart/status
    -h, --help      显示帮助

命令:
  run     启动隧道
  stop    停止服务
  restart 重启服务
  status  查看运行状态
  help    显示帮助

示例:
  ./cf-tunnel.sh run
  ./cf-tunnel.sh stop
  ./cf-tunnel.sh restart
  ./cf-tunnel.sh status
  ./cf-tunnel.sh -e "test@example.com" -k "xxxxx" -d "app.example.com" -n "app" -p "3000" -c run
HLP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--email)
        CF_EMAIL="$2"
        shift 2
        ;;
      -k|--key)
        CF_GLOBAL_KEY="$2"
        shift 2
        ;;
      -d|--domain)
        DOMAIN="$2"
        shift 2
        ;;
      -n|--name)
        TUNNEL_NAME="$2"
        shift 2
        ;;
      -p|--port)
        LOCAL_PORT="$2"
        shift 2
        ;;
      -c|--command)
        COMMAND="$2"
        shift 2
        ;;
      run|stop|restart|status|help)
        COMMAND="$1"
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        print_error "未知参数: $1"
        show_help
        exit 1
        ;;
    esac
  done

  COMMAND="${COMMAND:-help}"
}

main() {
  local cmd="${1:-help}"

  if [[ "$cmd" == -* ]] || [[ "$1" == --* ]]; then
    parse_args "$@"
    cmd="${COMMAND:-help}"
  fi

  case "$cmd" in
    run) run_tunnel ;;
    stop) stop_cloudflared ;;
    restart) stop_cloudflared; run_tunnel ;;
    status) show_tunnel_status ;;
    help|--help|-h) show_help ;;
    *) show_help; exit 1 ;;
  esac
}

main "$@"
