# x-tunnel

一个自动化管理 Cloudflare Tunnel 的 Bash 脚本，用于快速部署 x-tunnel 服务并通过 Cloudflare Argo Tunnel 暴露到公网。

## 功能特性

- **一键部署**：直接下载脚本，无需克隆整个仓库
- **自动化安装**：自动安装依赖、下载二进制文件、配置并启动服务
- **API 模式**：通过 Cloudflare API 自动创建固定隧道（Named Tunnel）
- **智能端口管理**：自动检测空闲端口，动态配置 ingress 规则
- **同名隧道处理**：检测到同名隧道时自动删除并重建（支持重试机制）
- **日志管理**：内置日志轮转，支持 logrotate 系统集成
- **多架构支持**：自动识别系统架构（amd64/arm64/386）
- **灵活认证**：支持 Cloudflare API Token 或 Global API Key

## 系统要求

- Linux 操作系统（Debian/Ubuntu/CentOS/RHEL/Alpine 等）
- root 权限或 sudo 访问权限
- 已注册 Cloudflare 账号并添加域名

## 快速开始

### 1. 下载脚本并赋予执行权限

```bash
curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/x-tunnel/suoha-x.sh -o suoha-x.sh
chmod +x suoha-x.sh
```

### 2. 创建并配置 .env 文件

参考以下模板创建 `.env` 文件：

```bash
cat > .env << 'EOF'
########################
# Cloudflare 认证（二选一）
########################

# 推荐：API Token（更安全）
cf_api_token="YOUR_CLOUDFLARE_API_TOKEN"

# 备选：Global API Key（不推荐）
# cf_email="you@example.com"
# cf_global_key="YOUR_CLOUDFLARE_GLOBAL_API_KEY"

########################
# 隧道与域名配置（必填）
########################

# 要绑定的完整域名
cf_domain="x-tunnel-1.example.com"

# 域名所在的 Zone
cf_zone="example.com"

# Tunnel 名称
cf_tunnel_name="x-tunnel-1"

########################
# 可选配置
########################

# x-tunnel 监听端口（留空则自动分配）
# port="30000"

# cloudflared IP 版本（4 或 6，默认 4）
ips="4"
EOF
```

然后编辑 `.env` 文件，填入你的真实配置：

```bash
nano .env
```

### 3. 启动服务

```bash
./suoha-x.sh install -m api -e
```

## 使用说明

### 命令格式

```bash
./suoha-x.sh <command> [options]
```

### 可用命令

| 命令 | 说明 |
|------|------|
| `install` | 安装并启动服务 |
| `stop` | 停止所有服务 |
| `remove` | 卸载并清理所有资源 |
| `status` | 查看服务运行状态 |

### 参数选项

| 选项 | 说明 |
|------|------|
| `-m, --mode` | 运行模式（仅支持 `api`） |
| `-e, --env` | 从 `.env` 文件加载配置 |
| `-z, --zone` | 指定 Cloudflare Zone |
| `-d, --domain` | 指定绑定的域名 |
| `-n, --name` | 指定 Tunnel 名称 |
| `-p, --port` | 指定 x-tunnel 监听端口 |
| `-i, --ips` | cloudflared IP 版本（4 或 6） |
| `-x, --token` | x-tunnel 认证 token |
| `-E, --email` | Cloudflare 邮箱 |
| `-G, --global-key` | Cloudflare Global API Key |
| `-T, --api-token` | Cloudflare API Token |
| `-h, --help` | 显示帮助信息 |

### 使用示例

```bash
# 使用 .env 文件启动（推荐）
./suoha-x.sh install -m api -e

# 命令行直接指定参数（不使用 .env 文件）
./suoha-x.sh install -m api \
  -T "YOUR_API_TOKEN" \
  -d "tunnel.example.com" \
  -z "example.com" \
  -n "my-tunnel"

# 停止服务
./suoha-x.sh stop

# 查看状态
./suoha-x.sh status

# 完全卸载
./suoha-x.sh remove
```

## 配置说明

### Cloudflare API Token 权限要求

创建 API Token 时需要以下权限：

- **Account**: Cloudflare Tunnel (Edit)
- **Zone**: DNS (Edit)

### 环境变量说明

| 变量名 | 必填 | 说明 |
|--------|------|------|
| `cf_api_token` | 二选一 | Cloudflare API Token（推荐） |
| `cf_email` | 二选一 | Cloudflare 账号邮箱 |
| `cf_global_key` | 二选一 | Cloudflare Global API Key |
| `cf_domain` | 是 | 要绑定的完整域名 |
| `cf_zone` | 强烈建议 | 域名所在的 Zone |
| `cf_tunnel_name` | 是 | Tunnel 名称 |
| `token` | 否 | x-tunnel 认证 token |
| `port` | 否 | x-tunnel 监听端口（留空则自动分配） |
| `ips` | 否 | cloudflared IP 版本（默认 4） |
| `LOG_DIR` | 否 | 日志目录（默认当前目录） |

## 常见问题

### 错误码 1022：无法删除 Tunnel（active connections）

当脚本检测到同名 Tunnel 时，会先尝试删除旧 Tunnel 再创建新的。如果 Cloudflare 返回 1022（提示 Cannot delete tunnel because it has active connections），说明该 Tunnel 仍被某个 cloudflared 实例认为"在线"，因此 Cloudflare 拒绝删除。

**解决方法：**

1. **先执行停止命令（推荐）：**
   ```bash
   ./suoha-x.sh stop
   ```

2. **如果仍然报错，手动执行 cleanup：**
   ```bash
   ./cloudflared-linux tunnel cleanup <TUNNEL_ID>
   ```

3. **cleanup 需要 origin certificate（cert.pem）**。若提示找不到 cert.pem，请先执行：
   ```bash
   ./cloudflared-linux tunnel login
   ```
   然后将证书放到默认路径（例如 `~/.cloudflared/cert.pem`），或通过 `--origincert` 或环境变量 `TUNNEL_ORIGIN_CERT` 指定证书路径。

### 日志位置

默认日志保存在脚本运行目录：

- `x-tunnel.log` - x-tunnel 服务日志
- `cloudflared.log` - cloudflared 日志
- `opera.log` - opera 服务日志（如启用）

可通过 `LOG_DIR` 环境变量自定义日志目录。

## 项目文件

```
工作目录/
├── suoha-x.sh      # 主脚本文件（下载）
├── .env            # 本地配置文件（手动创建）
├── .tunnel_info    # 自动生成的隧道信息
└── *.log           # 日志文件
```

## 许可证

MIT License

## 致谢

- [cloudflared](https://github.com/cloudflare/cloudflared) - Cloudflare 官方隧道客户端
- [x-tunnel](https://www.baipiao.eu.org/) - x-tunnel 二进制分发
