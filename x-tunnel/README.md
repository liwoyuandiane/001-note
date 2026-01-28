# suoha-x.sh - 一键部署 x-tunnel + Cloudflare Argo 代理服务

一个自动化部署脚本，用于在 Linux 系统上快速搭建基于 **x-tunnel** + **Cloudflare Argo Tunnel** 的代理服务，支持临时隧道/持久化隧道切换、地区代理（opera-proxy）、token 验证等功能。

## 🌟 功能特性

- 自动适配主流 Linux 发行版（Debian/Ubuntu/CentOS/Fedora/Alpine）
- 自动检测 CPU 架构（x86_64/i386/arm64），下载对应版本程序
- 支持临时 Argo 隧道（默认）和持久化隧道（通过 `-t` 参数绑定令牌）
- 可选启用 opera-proxy 前置代理（支持 us/eu/ap 地区）
- 支持 x-tunnel 身份令牌验证（`-x` 参数）
- 支持 IPv4/IPv6 双栈模式（`-c` 参数）
- 提供服务启停、状态查看、缓存清理功能

## 🚀 快速开始

### 1. 一键下载并执行脚本

```bash
# 使用 curl 下载
curl -L -o suoha-x.sh https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/x-tunnel/suoha-x.sh && chmod +x suoha-x.sh

# 或使用 wget 下载（若系统无 curl）
wget -O suoha-x.sh https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/x-tunnel/suoha-x.sh && chmod +x suoha-x.sh
```

### 2. 运行脚本

```bash
# 快速部署（临时隧道，重启失效）
./suoha-x.sh

# 使用固定隧道（永久有效）
./suoha-x.sh -t "your_account_tag,your_secret,your_tunnel_id,your_domain.com"

# 启用 opera-proxy 前置代理（eu/us/ap）
./suoha-x.sh -o -r eu

# 启用 x-tunnel 令牌验证
./suoha-x.sh -x "your_xtoken"

# 使用 IPv6 模式
./suoha-x.sh -c
```

## 📖 命令行参数

| 参数 | 说明 |
|------|------|
| `-o, --opera` | 启用 opera-proxy 前置代理 |
| `-c, --ipv6` | 使用 IPv6 模式（默认 IPv4） |
| `-x TOKEN` | 设置 x-tunnel 身份验证令牌 |
| `-t CRED` | 使用固定隧道（格式: `account_tag,tunnel_secret,tunnel_id,domain`） |
| `-r REGION` | 设置地区（us/eu/ap，默认 us） |
| `status` | 查看服务运行状态 |
| `stop` | 停止所有服务 |
| `clean` | 停止服务并清理下载的文件 |
| `-h, --help` | 显示帮助信息 |

## 📊 常用命令

```bash
# 查看服务状态
./suoha-x.sh status

# 停止所有服务
./suoha-x.sh stop

# 清理所有下载的文件
./suoha-x.sh clean

# 查看运行日志
screen -r argo
screen -r x-tunnel

# 分离 screen 会话（不停止服务）
# 按 Ctrl+A 然后按 D
```

## 🔧 获取 Cloudflare 固定隧道凭证

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 进入 Zero Trust > Networks > Tunnels
3. 创建或使用已有隧道，获取以下信息：
   - **Account Tag**: 账户标签
   - **Tunnel Secret**: 隧道密钥
   - **Tunnel ID**: 隧道ID
   - **Domain**: 绑定的域名

## 🏗️ 服务架构

```
[Client] <--HTTPS--> [Cloudflare Argo] <--HTTP--> [x-tunnel] <--WebSocket--> [Target]
                           |
                   [opera-proxy] (optional)
```

服务使用 GNU screen 在后台运行，包含三个会话：
- `x-tunnel`: WebSocket 代理服务
- `argo`: Cloudflare 隧道守护进程
- `opera`: 可选的地区代理

## ⚠️ 注意事项

- 脚本需要 root 权限进行安装和服务管理
- 快速隧道生成的临时域名在重启后会失效
- 固定隧道需要有效的 Cloudflare 账户凭证
- 确保服务器防火墙允许出站连接
- 建议定期更新下载的二进制文件

## 📜 许可证

MIT License - 自由使用和修改
