# OpenCode + Cloudflare Tunnel 一键安装脚本

一键在 Linux 服务器上安装 OpenCode 并通过 Cloudflare Tunnel 暴露公网访问。

[English](README.md) | 简体中文

## 功能特性

- 一键安装 OpenCode 服务端
- 自动下载并配置 Cloudflare Tunnel (cloudflared)
- 支持自定义端口、用户名、密码（密码可选）
- 支持后台持久运行
- 便捷的服务管理命令（启动、停止、重启、状态查看）
- 自动生成公网访问链接

## 快速开始

### 一键安装命令

将以下命令中的参数修改为你的值，然后复制到服务器执行：

```bash
# 基本用法（不使用密码）
bash <(curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh) install -t 你的cf密钥

# 使用密码
bash <(curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh) install -P 你的密码 -t 你的cf密钥

# 自定义端口和用户名
bash <(curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh) install -p 56780 -u admin -P 你的密码 -t 你的cf密钥
```

### 手动下载脚本执行

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh

# 添加执行权限
chmod +x opencode-server-cloudflared.sh

# 安装并启动服务（不使用密码）
./opencode-server-cloudflared.sh install -t 你的cf密钥

# 安装并启动服务（使用密码）
./opencode-server-cloudflared.sh install -P 你的密码 -t 你的cf密钥
```

## 参数说明

| 参数 | 说明 | 默认值 | 是否必填 |
|------|------|--------|----------|
| `-p, --port` | OpenCode 服务端口 | 56780 | 否 |
| `-u, --user` | 登录用户名 | opencode | 否 |
| `-P, --password` | 登录密码 | - | 否 |
| `-t, --token` | Cloudflare Tunnel 密钥 | - | **是** |

## 使用示例

```bash
# 示例 1：无密码安装
./opencode-server-cloudflared.sh install -t eyJh...

# 示例 2：使用密码安装
./opencode-server-cloudflared.sh install -P MyPassword123 -t eyJh...

# 示例 3：自定义端口和用户名
./opencode-server-cloudflared.sh install -p 8080 -u admin -P MyPassword123 -t eyJh...

# 示例 4：查看服务状态
./opencode-server-cloudflared.sh status

# 示例 5：停止服务
./opencode-server-cloudflared.sh stop

# 示例 6：重启服务
./opencode-server-cloudflared.sh restart

# 示例 7：查看帮助
./opencode-server-cloudflared.sh --help
```

## 获取 Cloudflare Tunnel 密钥

1. 访问 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. 进入 **Networks** > **Tunnels**
3. 点击 **Add a tunnel** 创建新隧道
4. 选择 **Cloudflare** 作为类型
5. 复制生成的隧道密钥（以 `eyJh` 开头）

或者使用 quick tunnel（临时使用，无需密钥）：

```bash
# 安装 cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# 创建临时隧道（无需登录）
cloudflared tunnel --url http://localhost:56780
```

## 服务管理

### 查看状态

```bash
./opencode-server-cloudflared.sh status
```

输出示例：
```
========================================
          服务状态
========================================

[运行中] OpenCode (PID: 12345)
[运行中] Cloudflared (PID: 12346)

========================================
          公开访问链接
========================================
https://xxxxx.trycloudflare.com
```

### 停止服务

```bash
./opencode-server-cloudflared.sh stop
```

### 重启服务

```bash
./opencode-server-cloudflared.sh restart
```

## Windows 客户端连接

服务启动后，在 Windows OpenCode 客户端中配置：

- **服务器地址**：`https://xxxxx.trycloudflare.com`
- **用户名**：`opencode`（或自定义）
- **密码**：如果你设置了密码则需要填写，否则留空

## 日志文件

所有日志保存在 `~/.opencode/` 目录：

- OpenCode 日志：`~/.opencode/opencode.log`
- Cloudflared 日志：`~/.opencode/cloudflared.log`

查看日志：
```bash
# 实时查看 OpenCode 日志
tail -f ~/.opencode/opencode.log

# 实时查看 Cloudflared 日志
tail -f ~/.opencode/cloudflared.log
```

## 系统要求

- Linux 服务器（Ubuntu 20.04+ / Debian 10+ / CentOS 7+）
- x86_64 或 ARM64 架构
- 已安装 curl 或 wget
- 具有 sudo 权限的用户（推荐非 root）

## 常见问题

### Q: 安装失败怎么办？

```bash
# 1. 检查日志
tail -f ~/.opencode/opencode.log

# 2. 确保端口未被占用
netstat -tlnp | grep 56780

# 3. 重新安装
./opencode-server-cloudflared.sh stop
./opencode-server-cloudflared.sh install -t 你的cf密钥
```

### Q: 如何修改端口或密码？

```bash
# 停止当前服务
./opencode-server-cloudflared.sh stop

# 使用新参数重新安装
./opencode-server-cloudflared.sh install -p 新端口 -u 新用户名 -P 新密码 -t 你的cf密钥
```

### Q: cloudflared 下载失败？

脚本支持自动下载，如果下载失败可以手动下载：

```bash
# x86_64
wget -O ~/.opencode/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64

# ARM64
wget -O ~/.opencode/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64

chmod +x ~/.opencode/cloudflared
```

### Q: Docker 容器中能用吗？

可以，但需要注意：
1. 端口需要映射到宿主机
2. 需要使用 host 网络模式或配置端口转发
3. Cloudflare Tunnel 需要公网出站权限

## 许可证

本项目遵循 MIT 许可证。

## 参考链接

- [OpenCode 官方文档](https://docs.opencode.ai/)
- [OpenCode GitHub](https://github.com/anomalyco/opencode)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
