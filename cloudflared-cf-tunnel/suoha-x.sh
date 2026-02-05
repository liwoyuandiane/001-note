#!/usr/bin/env bash
# suoha x-tunnel 管理脚本（最终版）
#
# ✅ 修复/特性：
# - Zone ID 查询：逐个尝试候选域名；支持 -z/--zone 或 cf_zone 强制指定
# - API 模式：先启动 x-tunnel（端口可随机）→ PID 探测真实监听端口 → 写入远端 ingress → 启动 cloudflared
# - 远端配置 API 使用正确路径：/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations
# - 隧道同名存在：先删后建（删除后等待5秒，检测是否仍存在，最多重试3次，仍失败则退出）
# - remove：停止服务 + 删除远端(可选) + 删除本地二进制 + 删除日志/轮转/pid + 删除 logrotate 配置
# - 日志默认在脚本运行目录（pwd）：x-tunnel.log / cloudflared.log / opera.log

set -euo pipefail

# ------------------- 输出 -------------------
print_success(){ echo -e "\033[0;32m✓ $*\033[0m"; }
print_error(){ echo -e "\033[0;31m✗ $*\033[0m"; }
print_info(){ echo -e "\033[0;36mℹ $*\033[0m"; }
print_warning(){ echo -e "\033[0;33m⚠ $*\033[0m"; }

# ------------------- 权限/包管理 -------------------
as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    print_error "需要 root 权限或 sudo 来安装依赖"
    return 1
  fi
}

PM_UPDATE="apt update"
PM_INSTALL="apt -y install"

detect_pkg_manager() {
  if [ -f /etc/os-release ]; then
    local os_id
    os_id=$(grep -i '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr 'A-Z' 'a-z')
    case "$os_id" in
      debian|ubuntu) PM_UPDATE="apt update"; PM_INSTALL="apt -y install" ;;
      centos|rhel|rocky|almalinux|ol|amzn|fedora) PM_UPDATE="yum -y update"; PM_INSTALL="yum -y install" ;;
      alpine) PM_UPDATE="apk update"; PM_INSTALL="apk add -f" ;;
      *) PM_UPDATE="apt update"; PM_INSTALL="apt -y install" ;;
    esac
  fi
}
detect_pkg_manager

# ------------------- 日志与轮转（默认：pwd） -------------------
LOG_DIR="${LOG_DIR:-}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-10}"
LOG_ROTATE_KEEP="${LOG_ROTATE_KEEP:-7}"
LOG_USE_LOGROTATE="${LOG_USE_LOGROTATE:-1}"

init_logging() {
  if [ -z "${LOG_DIR}" ]; then
    LOG_DIR="$(pwd)"
  fi
  mkdir -p "$LOG_DIR" 2>/dev/null || true
}

rotate_log_size() {
  local file="$1"
  local max_bytes=$((LOG_MAX_SIZE_MB * 1024 * 1024))
  [ -f "$file" ] || return 0
  local size
  size=$(stat -c '%s' "$file" 2>/dev/null || echo 0)
  [ "$size" -lt "$max_bytes" ] && return 0

  local i
  for ((i=LOG_ROTATE_KEEP; i>=1; i--)); do
    [ -f "${file}.${i}" ] && {
      [ "$i" -ge "$LOG_ROTATE_KEEP" ] && rm -f "${file}.${i}"
      mv -f "${file}.${i}" "${file}.$((i+1))"
    } 2>/dev/null || true

    [ -f "${file}.${i}.gz" ] && {
      [ "$i" -ge "$LOG_ROTATE_KEEP" ] && rm -f "${file}.${i}.gz"
      mv -f "${file}.${i}.gz" "${file}.$((i+1)).gz"
    } 2>/dev/null || true
  done

  mv -f "$file" "${file}.1" 2>/dev/null || true
  command -v gzip >/dev/null 2>&1 && gzip -f "${file}.1" >/dev/null 2>&1 || true
  : > "$file" 2>/dev/null || true
}

setup_logrotate() {
  [ "$LOG_USE_LOGROTATE" = "1" ] || return 0
  command -v logrotate >/dev/null 2>&1 || return 0
  [ "${EUID:-$(id -u)}" -eq 0 ] || return 0
  [ -d /etc/logrotate.d ] || return 0

  init_logging
  cat > /etc/logrotate.d/suoha-x-tunnel <<EOF
$LOG_DIR/*.log {
  daily
  rotate 7
  size 10M
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF
}

# ------------------- 工具 -------------------
get_free_port() {
  while true; do
    local PORT=$((RANDOM + 1024))
    if ! lsof -i TCP:"$PORT" >/dev/null 2>&1; then
      echo "$PORT"; return 0
    fi
  done
}

# screen 后台运行 + 日志 + pid
screen_run_logged_pid() {
  # <session> <logfile> <pidfile> <cmd> [args...]
  local session="$1" logfile="$2" pidfile="$3"; shift 3
  init_logging
  rotate_log_size "$logfile"
  local cmd="" arg
  for arg in "$@"; do cmd+=" $(printf '%q' "$arg")"; done
  cmd="${cmd# }"
  screen -dmS "$session" bash -lc "echo \"\$\$\" >\"$pidfile\"; exec >>\"$logfile\" 2>&1; echo \"[$(date '+%F %T')] START $session\"; exec $cmd"
}

get_listen_port_by_pid() {
  local pid="$1" timeout="${2:-20}"
  local t=0
  while [ "$t" -lt "$timeout" ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    local name port
    name=$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $9}' | head -n 1)
    if [ -n "$name" ]; then
      port=$(echo "$name" | awk -F: '{print $NF}')
      [[ "$port" =~ ^[0-9]+$ ]] && { echo "$port"; return 0; }
    fi
    sleep 1; t=$((t+1))
  done
  return 1
}

curl_fetch() {
  local out="$1" url="$2"
  curl -fL --retry 3 --retry-connrefused --connect-timeout 10 --max-time 120 -o "$out" "$url"
}

json_get() {
  local json="$1" jq_expr="$2" fallback_regex="$3"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r "$jq_expr" 2>/dev/null
  else
    echo "$json" | sed -nE "s/.*$fallback_regex.*/\\1/p" | head -n 1
  fi
}

# ------------------- 依赖安装 -------------------
setup_environment() {
  print_info "正在检查并安装依赖..."
  as_root bash -c "$PM_UPDATE" >/dev/null 2>&1 || true
  local deps=(screen curl lsof tar gzip dos2unix jq logrotate)
  local d
  for d in "${deps[@]}"; do
    if ! command -v "$d" >/dev/null 2>&1; then
      print_info "安装 $d..."
      as_root bash -c "$PM_INSTALL $d" >/dev/null 2>&1 || true
    fi
  done
  init_logging
  setup_logrotate || true
  print_success "环境准备完成"
  print_info "日志目录: $LOG_DIR"
}

# ------------------- .env 加载 -------------------
load_env_file() {
  if [ ! -f .env ]; then
    print_error "未找到 .env 文件"; return 1
  fi
  command -v dos2unix >/dev/null 2>&1 && dos2unix .env >/dev/null 2>&1 || true

  while IFS='=' read -r key value; do
    [[ -z "${key// }" ]] && continue
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    key="${key%%[[:space:]]*}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"* ]]; then
      value="${value#\"}"; value="${value%%\"*}"
    elif [[ "$value" == \'* ]]; then
      value="${value#\'}"; value="${value%%\'*}"
    else
      value=$(echo "$value" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
    fi
    export "$key=$value"
  done < .env

  cf_email="${cf_email:-${CF_EMAIL:-}}"
  cf_global_key="${cf_global_key:-${CF_GLOBAL_KEY:-}}"
  cf_api_token="${cf_api_token:-${CF_API_TOKEN:-}}"
  cf_domain="${cf_domain:-${CF_DOMAIN:-}}"
  cf_zone="${cf_zone:-${CF_ZONE:-}}"
  cf_tunnel_name="${cf_tunnel_name:-${CF_TUNNEL_NAME:-x-tunnel-auto}}"
  token="${token:-}"
  port="${port:-}"
  ips="${ips:-4}"
  opera="${opera:-0}"
  country="${country:-AM}"
}

show_config() {
  print_info "配置信息:"
  print_info "  CF Email: ${cf_email:-<empty>}"
  print_info "  CF Domain: ${cf_domain:-<empty>}"
  print_info "  CF Zone: ${cf_zone:-<auto>}"
  print_info "  Tunnel Name: ${cf_tunnel_name:-<empty>}"
  if [ -n "${cf_api_token:-}" ]; then
    print_info "  Auth: API Token（已设置）"
  else
    print_info "  Auth: Global Key（已设置）"
  fi
}

# ------------------- Cloudflare API（header 不拆分） -------------------
cf_api() {
  local method="$1" url="$2" data="${3:-}"
  local auth_args=()
  if [ -n "${cf_api_token:-}" ]; then
    auth_args=(-H "Authorization: Bearer ${cf_api_token}")
  else
    auth_args=(-H "X-Auth-Email: ${cf_email}" -H "X-Auth-Key: ${cf_global_key}")
  fi

  if [ -n "$data" ]; then
    curl -sS --max-time 30 -X "$method" "$url" "${auth_args[@]}" -H "Content-Type: application/json" -d "$data" 2>/dev/null || true
  else
    curl -sS --max-time 30 -X "$method" "$url" "${auth_args[@]}" -H "Content-Type: application/json" 2>/dev/null || true
  fi
}

# Zone ID：逐个尝试（支持 -z/--zone 强制）
get_zone_id() {
  local target
  target="${cf_zone:-$1}"
  [ -z "$target" ] && return 1

  local parts len
  IFS='.' read -ra parts <<< "$target"
  len=${#parts[@]}

  local candidates=()
  for ((i=2; i<=len; i++)); do
    local d=""
    for ((j=len-i; j<len; j++)); do
      if [ -z "$d" ]; then d="${parts[$j]}"; else d="$d.${parts[$j]}"; fi
    done
    candidates+=("$d")
  done

  local uniq=() seen=$'\n' c
  for c in "${candidates[@]}"; do
    if [[ "$seen" != *$'\n'"$c"$'\n'* ]]; then
      uniq+=("$c"); seen+="$c"$'\n'
    fi
  done

  local root response success count zone_id
  for root in "${uniq[@]}"; do
    print_info "尝试查询域名: $root" >&2
    response=$(cf_api GET "https://api.cloudflare.com/client/v4/zones?name=$root")
    success=$(json_get "$response" '.success // empty' '"success":(true|false)')
    [ "$success" != "true" ] && continue
    count=$(json_get "$response" '.result_info.total_count // 0' '"total_count":([0-9]+)')
    [ -z "$count" ] && count=0
    [ "$count" = "0" ] && continue
    zone_id=$(json_get "$response" '.result[0].id // empty' '"id":"([a-f0-9-]+)"')
    [ -n "$zone_id" ] && [ "$zone_id" != "null" ] && { echo "$zone_id"; return 0; }
  done
  return 1
}

get_account_id() {
  local resp success
  resp=$(cf_api GET "https://api.cloudflare.com/client/v4/accounts")
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

# ✅ 关键：远端 Tunnel 配置 API 必须用 cfd_tunnel
cf_tunnel_base() { echo "https://api.cloudflare.com/client/v4/accounts/$1/cfd_tunnel"; }

check_tunnel_exists() {
  local account_id="$1" name="$2"
  local resp success count
  resp=$(cf_api GET "$(cf_tunnel_base "$account_id")?name=$name")
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  count=$(json_get "$resp" '.result_info.total_count // 0' '"total_count":([0-9]+)')
  [ -z "$count" ] && count=0
  [ "$count" = "0" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

delete_cloudflare_tunnel() {
  local account_id="$1" tunnel_id="$2"
  cf_api DELETE "$(cf_tunnel_base "$account_id")/$tunnel_id" >/dev/null 2>&1 || true
}

# ------------------- ✅ 隧道删除：5次重试，前3次间隔5秒，后2次间隔3分钟 -------------------
ensure_tunnel_deleted() {
  local account_id="$1" name="$2"
  local max_try=5
  local delay=5

  local attempt=1
  while [ "$attempt" -le "$max_try" ]; do
    local tid=""
    tid=$(check_tunnel_exists "$account_id" "$name" 2>/dev/null || true)

    # 不存在：删除成功（或本来就没有）
    if [ -z "$tid" ] || [ "$tid" = "null" ]; then
      return 0
    fi

    # 第4次开始进入长等待模式
    if [ "$attempt" -eq 4 ]; then
      delay=180
      print_info "隧道删除仍在进行，进入长等待模式（3分钟）..." >&2
    fi

    print_warning "检测到同名隧道仍存在（ID: $tid），开始第 ${attempt}/${max_try} 次删除..." >&2
    delete_cloudflare_tunnel "$account_id" "$tid"

    # 删除后等待
    sleep "$delay"

    # 再次检查
    local tid2=""
    tid2=$(check_tunnel_exists "$account_id" "$name" 2>/dev/null || true)
    if [ -z "$tid2" ] || [ "$tid2" = "null" ]; then
      print_success "隧道删除成功（name=$name）" >&2
      return 0
    fi

    attempt=$((attempt+1))
  done

  local last=""
  last=$(check_tunnel_exists "$account_id" "$name" 2>/dev/null || true)
  print_error "删除失败：隧道（name=$name）在重试 ${max_try} 次后仍存在（ID: ${last:-unknown}）。请稍后重试或在 Cloudflare 面板手动删除。" >&2
  return 1
}

create_cloudflare_tunnel() {
  local account_id="$1" name="$2"
  local existing
  existing=$(check_tunnel_exists "$account_id" "$name" || true)

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    print_warning "隧道已存在（$existing），先删除再创建" >&2
    # ✅ 删除失败直接返回（阻止后续创建）
    ensure_tunnel_deleted "$account_id" "$name" || return 1
  fi

  local data resp success
  data=$(printf '{"name":"%s"}' "$name")
  resp=$(cf_api POST "$(cf_tunnel_base "$account_id")" "$data")
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
  local account_id="$1" tunnel_id="$2" hostname="$3" xt_port="$4"
  local cfg resp success
  cfg=$(cat <<EOF
{
  "config": {
    "ingress": [
      {"hostname": "$hostname", "service": "http://127.0.0.1:$xt_port", "originRequest": {"noTLSVerify": true}},
      {"service": "http_status:404"}
    ]
  }
}
EOF
)
  resp=$(cf_api PUT "$(cf_tunnel_base "$account_id")/$tunnel_id/configurations" "$cfg")
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" = "true" ]
}

gen_dns_payload() {
  local hostname="$1" tunnel_id="$2"
  cat <<EOF
{
  "type": "CNAME",
  "name": "$hostname",
  "content": "$tunnel_id.cfargotunnel.com",
  "ttl": 1,
  "proxied": true
}
EOF
}

check_dns_record() {
  local zone_id="$1" hostname="$2"
  local resp success count
  resp=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$hostname&type=CNAME")
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  count=$(json_get "$resp" '.result_info.total_count // 0' '"total_count":([0-9]+)')
  [ -z "$count" ] && count=0
  [ "$count" = "0" ] && return 1
  json_get "$resp" '.result[0].id // empty' '"id":"([a-f0-9-]+)"'
}

delete_dns_record() {
  local zone_id="$1" rid="$2"
  cf_api DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rid" >/dev/null 2>&1 || true
}

create_dns_record() {
  local zone_id="$1" hostname="$2" tunnel_id="$3"
  local data resp success
  data=$(gen_dns_payload "$hostname" "$tunnel_id")
  resp=$(cf_api POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" "$data")
  success=$(json_get "$resp" '.success // empty' '"success":(true|false)')
  [ "$success" != "true" ] && return 1
  json_get "$resp" '.result.id // empty' '"id":"([a-f0-9-]+)"'
}

save_tunnel_info() {
  local tunnel_id="$1" hostname="$2" dns_record_id="$3" xt_port="$4" tunnel_name="$5" zone_id="$6" account_id="$7"
  cat > .tunnel_info <<EOF
# auto-generated
tunnel_id=$tunnel_id
hostname=$hostname
dns_record_id=$dns_record_id
xt_port=$xt_port
tunnel_name=$tunnel_name
zone_id=$zone_id
account_id=$account_id
EOF
}

load_tunnel_info() {
  [ -f .tunnel_info ] || return 1
  # shellcheck disable=SC1091
  source .tunnel_info
}

# ------------------- 服务管理 -------------------
stop_all_services() {
  print_info "正在停止所有服务..."
  screen -wipe >/dev/null 2>&1 || true
  for s in x-tunnel opera argo; do
    screen -S "$s" -X quit 2>/dev/null || true
  done
  print_success "所有服务已停止"
}

show_status() {
  echo ""
  echo "========== 服务状态 =========="
  for s in x-tunnel opera argo; do
    if screen -ls 2>/dev/null | grep -q "\.${s}[[:space:]]"; then
      print_success "$s 正在运行"
    else
      print_error "$s 未运行"
    fi
  done
  init_logging
  echo "LOG_DIR: $LOG_DIR"
}

# ------------------- 下载二进制 -------------------
download_binaries() {
  local arch cf_arch xt_arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) cf_arch="amd64"; xt_arch="amd64" ;;
    i386|i686) cf_arch="386"; xt_arch="386" ;;
    arm64|aarch64) cf_arch="arm64"; xt_arch="arm64" ;;
    *) print_error "不支持的架构: $arch"; exit 1 ;;
  esac

  [ -f x-tunnel-linux ] || { print_info "下载 x-tunnel..."; curl_fetch x-tunnel-linux "https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-$xt_arch"; chmod +x x-tunnel-linux; }
  [ -f cloudflared-linux ] || { print_info "下载 cloudflared..."; curl_fetch cloudflared-linux "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch"; chmod +x cloudflared-linux; }
  print_success "二进制文件就绪"
}

# ------------------- API 模式（核心） -------------------
api_mode() {
  print_info "启动 API 模式..."
  setup_environment
  stop_all_services
  download_binaries
  init_logging

  ips="${ips:-4}"

  [ -n "${cf_domain:-}" ] || { print_error "缺少 cf_domain"; exit 1; }
  if [ -z "${cf_api_token:-}" ] && { [ -z "${cf_email:-}" ] || [ -z "${cf_global_key:-}" ]; }; then
    print_error "缺少 Cloudflare 认证信息"; exit 1
  fi

  print_info "正在查询 Zone ID..."
  local ZONE_ID ACCOUNT_ID
  ZONE_ID=$(get_zone_id "$cf_domain") || { print_error "获取 Zone ID 失败"; exit 1; }
  ACCOUNT_ID=$(get_account_id) || { print_error "获取 Account ID 失败"; exit 1; }

  local TUNNEL_RESULT TUNNEL_ID TUNNEL_TOKEN
  TUNNEL_RESULT=$(create_cloudflare_tunnel "$ACCOUNT_ID" "$cf_tunnel_name") || { print_error "创建隧道失败"; exit 1; }
  TUNNEL_ID=$(echo "$TUNNEL_RESULT" | sed -n '1p')
  TUNNEL_TOKEN=$(echo "$TUNNEL_RESULT" | sed -n '2p')

  # 先启动 x-tunnel（端口可随机）
  local try_port xt_pid xt_port
  try_port="${port:-}"
  [ -z "$try_port" ] && try_port=$(get_free_port)

  if [ -n "${token:-}" ]; then
    screen_run_logged_pid x-tunnel "$LOG_DIR/x-tunnel.log" "$LOG_DIR/x-tunnel.pid" ./x-tunnel-linux -l "ws://127.0.0.1:$try_port" -token "$token"
  else
    screen_run_logged_pid x-tunnel "$LOG_DIR/x-tunnel.log" "$LOG_DIR/x-tunnel.pid" ./x-tunnel-linux -l "ws://127.0.0.1:$try_port"
  fi

  sleep 1
  xt_pid=$(cat "$LOG_DIR/x-tunnel.pid" 2>/dev/null || true)
  [ -z "$xt_pid" ] && { print_error "无法获取 x-tunnel PID"; exit 1; }

  xt_port=$(get_listen_port_by_pid "$xt_pid" 20 || true)
  [ -z "$xt_port" ] && { print_error "无法探测 x-tunnel 监听端口"; exit 1; }
  print_success "x-tunnel 已启动（PID: $xt_pid，端口: $xt_port）"

  # 写入远端 ingress
  if update_tunnel_config "$ACCOUNT_ID" "$TUNNEL_ID" "$cf_domain" "$xt_port"; then
    print_success "远端 ingress 已更新（service -> 127.0.0.1:$xt_port）"
  else
    print_warning "远端 ingress 更新失败（可能导致 503）"
  fi

  # DNS：先删再建
  local DNS_RECORD_ID
  DNS_RECORD_ID=$(check_dns_record "$ZONE_ID" "$cf_domain" || true)
  [ -n "$DNS_RECORD_ID" ] && delete_dns_record "$ZONE_ID" "$DNS_RECORD_ID" || true
  DNS_RECORD_ID=$(create_dns_record "$ZONE_ID" "$cf_domain" "$TUNNEL_ID" || true)

  save_tunnel_info "$TUNNEL_ID" "$cf_domain" "$DNS_RECORD_ID" "$xt_port" "$cf_tunnel_name" "$ZONE_ID" "$ACCOUNT_ID"

  # 最后启动 cloudflared
  ./cloudflared-linux update >/dev/null 2>&1 || true
  screen_run_logged_pid argo "$LOG_DIR/cloudflared.log" "$LOG_DIR/cloudflared.pid" ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel run --token "$TUNNEL_TOKEN"

  print_success "cloudflared 已启动"
  echo ""
  print_success "API 隧道创建/启动完成"
  echo "========================================"
  echo "模式: API（固定隧道）"
  echo "域名: $cf_domain"
  echo "Tunnel: $cf_tunnel_name"
  echo "Tunnel ID: $TUNNEL_ID"
  echo "x-tunnel 端口: $xt_port"
  echo "日志目录: $LOG_DIR"
  echo " - x-tunnel: $LOG_DIR/x-tunnel.log"
  echo " - cloudflared: $LOG_DIR/cloudflared.log"
  echo "========================================"
}

remove_all() {
  print_info "正在卸载..."
  init_logging
  stop_all_services

  if load_tunnel_info; then
    if [ -n "${cf_api_token:-}" ] || { [ -n "${cf_email:-}" ] && [ -n "${cf_global_key:-}" ]; }; then
      local acc
      acc="${account_id:-}"
      [ -z "$acc" ] && acc=$(get_account_id || true)

      [ -n "${dns_record_id:-}" ] && [ -n "${zone_id:-}" ] && delete_dns_record "$zone_id" "$dns_record_id" >/dev/null 2>&1 || true
      [ -n "${tunnel_id:-}" ] && [ -n "$acc" ] && delete_cloudflare_tunnel "$acc" "$tunnel_id" >/dev/null 2>&1 || true
    fi
    rm -f .tunnel_info 2>/dev/null || true
  fi

  rm -f cloudflared-linux x-tunnel-linux opera-linux 2>/dev/null || true
  rm -f "$LOG_DIR"/x-tunnel.log "$LOG_DIR"/cloudflared.log "$LOG_DIR"/opera.log 2>/dev/null || true
  rm -f "$LOG_DIR"/x-tunnel.log.* "$LOG_DIR"/cloudflared.log.* "$LOG_DIR"/opera.log.* 2>/dev/null || true
  rm -f "$LOG_DIR"/x-tunnel.pid "$LOG_DIR"/cloudflared.pid "$LOG_DIR"/opera.pid 2>/dev/null || true

  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -f /etc/logrotate.d/suoha-x-tunnel ]; then
    rm -f /etc/logrotate.d/suoha-x-tunnel 2>/dev/null || true
  fi

  print_success "卸载完成（已删除二进制与日志）"
}

show_help() {
cat <<'HLP'
用法:
  ./suoha-x.sh install -m api -e
  ./suoha-x.sh stop
  ./suoha-x.sh remove
  ./suoha-x.sh status
HLP
}

cli_mode() {
  local cmd="$1"; shift
  local mode="api" use_env=false

  while [ $# -gt 0 ]; do
    case "$1" in
      -m|--mode) mode="$2"; shift 2 ;;
      -e|--env) use_env=true; shift ;;
      -z|--zone) cf_zone="$2"; shift 2 ;;
      -d|--domain) cf_domain="$2"; shift 2 ;;
      -n|--name) cf_tunnel_name="$2"; shift 2 ;;
      -p|--port) port="$2"; shift 2 ;;
      -i|--ips) ips="$2"; shift 2 ;;
      -x|--token) token="$2"; shift 2 ;;
      -E|--email) cf_email="$2"; shift 2 ;;
      -G|--global-key) cf_global_key="$2"; shift 2 ;;
      -T|--api-token) cf_api_token="$2"; shift 2 ;;
      -h|--help) show_help; exit 0 ;;
      *) print_error "未知参数: $1"; show_help; exit 1 ;;
    esac
  done

  if [ "$use_env" = true ]; then
    load_env_file
  fi

  init_logging
  show_config

  case "$cmd" in
    install)
      if [ "$mode" = "api" ]; then
        api_mode
      else
        print_error "此精简版仅保留 api 模式（如需要 quick，我可以再加回去）"; exit 1
      fi
      ;;
    stop) stop_all_services ;;
    remove) remove_all ;;
    status) show_status ;;
    *) show_help; exit 1 ;;
  esac
}

main() {
  if [ $# -lt 1 ]; then
    show_help; exit 0
  fi
  case "$1" in
    install|stop|remove|status) cli_mode "$@" ;;
    -h|--help|help) show_help ;;
    *) show_help; exit 1 ;;
  esac
}

main "$@"