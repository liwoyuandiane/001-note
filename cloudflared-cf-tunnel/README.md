# Cloudflare Tunnel 简化配置脚本

将本地指定端口通过 Cloudflare Tunnel 快速绑定到域名，无需复杂的配置文件。

## 功能特性

- 一键启动/停止/重启 Cloudflare Tunnel
- 自动创建和配置隧道
- 自动管理 DNS 记录
- 进程锁机制，防止重复运行
- 精确的进程管理（PID 追踪）
- 安全的凭据存储（文件权限 600）
- 完善的错误处理和重试机制

## 环境要求

- Bash 4.0+
- `curl` 命令
- `jq`（可选，用于解析 JSON）
- Linux/macOS 系统

## 快速开始

### 一键下载并提权

```bash
curl -o cf-tunnel.sh https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/cloudflared-cf-tunnel/cf-tunnel.sh && chmod +x cf-tunnel.sh
```

### 启动隧道（命令行参数方式）

```bash
./cf-tunnel.sh -e "your-email@example.com" \
                -k "your-global-api-key" \
                -d "sub.example.com" \
                -n "my-tunnel" \
                -p "8080" \
                -c run
```

### 访问服务

打开浏览器访问 `https://sub.example.com`，即可访问本地 `http://127.0.0.1:8080` 的服务。

## 命令说明

### 启动隧道

```bash
./cf-tunnel.sh -e "your-email@example.com" -k "your-global-api-key" -d "sub.example.com" -n "my-tunnel" -p "8080" -c run
```

或使用环境变量方式：

```bash
export CF_EMAIL="your-email@example.com"
export CF_GLOBAL_KEY="your-global-api-key"
export DOMAIN="sub.example.com"
export TUNNEL_NAME="my-tunnel"
export LOCAL_PORT="8080"
./cf-tunnel.sh run
```

自动完成以下操作：
- 下载 cloudflared（如不存在）
- 停止现有服务（如运行中）
- 查询 Zone ID 和 Account ID
- 创建/重建隧道
- 配置隧道路由规则
- 创建/更新 DNS CNAME 记录
- 启动 cloudflared 守护进程

### 停止服务

```bash
./cf-tunnel.sh -c stop
```

或

```bash
./cf-tunnel.sh stop
```

### 重启服务

```bash
./cf-tunnel.sh -c restart
```

或

```bash
./cf-tunnel.sh restart
```

### 查看状态

```bash
./cf-tunnel.sh -c status
```

或

```bash
./cf-tunnel.sh status
```

### 显示帮助

```bash
./cf-tunnel.sh -h
```

或

```bash
./cf-tunnel.sh --help
```

或

```bash
./cf-tunnel.sh help
```

## 参数说明

### 命令行参数

| 参数 | 短参数 | 说明 | 对应环境变量 |
|------|--------|------|--------------|
| `--email` | `-e` | Cloudflare 账户邮箱 | CF_EMAIL |
| `--key` | `-k` | Cloudflare Global API Key | CF_GLOBAL_KEY |
| `--domain` | `-d` | 要绑定的域名 | DOMAIN |
| `--name` | `-n` | 隧道名称 | TUNNEL_NAME |
| `--port` | `-p` | 本地监听端口 | LOCAL_PORT |
| `--command` | `-c` | 执行的命令（run/stop/restart/status） | - |
| `--help` | `-h` | 显示帮助 | - |

### 环境变量

| 参数 | 说明 | 获取方式 |
|------|------|----------|
| `CF_EMAIL` | Cloudflare 账户邮箱 | 登录 Cloudflare 面板 |
| `CF_GLOBAL_KEY` | Global API Key | [获取链接](https://dash.cloudflare.com/profile/api-tokens) |
| `DOMAIN` | 要绑定的域名 | 需已在 Cloudflare 托管 |
| `TUNNEL_NAME` | 隧道名称 | 自定义，重复时自动重建 |
| `LOCAL_PORT` | 本地监听端口 | 需确保本地服务已启动 |

## 获取 API Key

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 点击右上角头像 → **My Profile**
3. 选择 **API Tokens** 标签
4. 在 **Global API Key** 区域点击 **View** 查看密钥

## 使用示例

### 示例 1：启动本地开发服务（命令行参数方式，推荐）

```bash
./cf-tunnel.sh -e "user@example.com" \
                -k "xxxxxxxxxxxxxx" \
                -d "dev.example.com" \
                -n "dev-tunnel" \
                -p "3000" \
                -c run
```

访问 `https://dev.example.com` 即可访问本地 3000 端口。

### 示例 2：启动本地开发服务（环境变量方式）

```bash
export CF_EMAIL="user@example.com"
export CF_GLOBAL_KEY="xxxxxxxxxxxxxx"
export DOMAIN="dev.example.com"
export TUNNEL_NAME="dev-tunnel"
export LOCAL_PORT="3000"
./cf-tunnel.sh run
```

### 示例 3：一行命令启动

```bash
./cf-tunnel.sh -e "user@example.com" -k "xxxxxxxxxxxxxx" -d "app.example.com" -n "app-tunnel" -p "8080" -c run
```

### 示例 4：混合使用（部分参数通过命令行，部分通过环境变量）

```bash
export CF_EMAIL="user@example.com"
export CF_GLOBAL_KEY="xxxxxxxxxxxxxx"
./cf-tunnel.sh -d "app.example.com" -n "app-tunnel" -p "8080" -c run
```

### 示例 5：使用环境变量文件

创建 `.env` 文件：

```bash
CF_EMAIL="user@example.com"
CF_GLOBAL_KEY="xxxxxxxxxxxxxx"
DOMAIN="myapp.example.com"
TUNNEL_NAME="myapp"
LOCAL_PORT="5000"
```

加载并运行：

```bash
set -a
source .env
set +a
./cf-tunnel.sh run
```

## 生成的文件

脚本运行后会生成以下文件：

| 文件 | 说明 | 权限 |
|------|------|------|
| `.tunnel_info` | 隧道配置信息（包含敏感 token） | 600 |
| `.tunnel_pid` | cloudflared 进程 PID | 644 |
| `cloudflared` | Cloudflare Tunnel 客户端二进制 | 755 |

**注意**：`.tunnel_info` 包含敏感信息，请妥善保管，不要提交到版本控制系统。

## 故障排除

### 隧道无法启动

1. 检查本地服务是否运行：`curl http://127.0.0.1:端口号`
2. 检查端口是否被占用：`./cf-tunnel.sh status`
3. 查看 cloudflared 日志

### DNS 记录未更新

1. 确认域名已在 Cloudflare 托管
2. 检查 API Key 是否正确
3. 查看脚本输出中的错误信息

### API 请求失败

1. 确认 CF_EMAIL 和 CF_GLOBAL_KEY 正确
2. 检查网络连接
3. 确认 API Key 未过期

### 脚本提示"脚本已在运行"

1. 删除锁文件：`rm -f /tmp/cf-tunnel.lock`
2. 重新运行脚本

## 技术架构

- **进程锁**：使用 `flock` 确保单实例运行
- **进程管理**：通过 PID 文件精确控制进程
- **并发安全**：锁机制防止多个实例同时操作
- **错误重试**：隧道删除操作支持重试（默认 3 次）
- **下载保护**：使用临时文件确保下载完整性

## 许可证

MIT License

## 相关链接

- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
