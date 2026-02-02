# OpenCode + Cloudflare Tunnel 一键安装脚本

快速搭建 OpenCode API 服务端并通过 Cloudflare Tunnel 暴露公网访问。

## 功能特性

- **一键部署**：自动安装 OpenCode + Cloudflared，快速上线
- **API 模式**：使用 `opencode serve` 启动无头 HTTP 服务器（适合 IDE 插件、程序化调用）
- **安全访问**：强制密码认证 + Cloudflare Tunnel 加密传输
- **跨域支持**：可选 CORS 配置，支持自定义前端接入
- **智能管理**：自动清理残留 PID、日志大小限制（10MB）
- **交互模式**：支持命令行参数和交互式部署两种方式

## 快速开始

### 一键安装（命令行模式）

```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && \
chmod +x opencode.sh && \
bash ./opencode.sh install -p 56780 -u opencode -P "Admin@12345678" -t YOUR_CF_TOKEN'
```

### 交互式部署

```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && \
chmod +x opencode.sh && \
bash ./opencode.sh interactive'
```

## 命令说明

| 命令 | 说明 |
|------|------|
| `install` | 安装并启动服务 |
| `status` | 查看服务状态和日志 |
| `stop` | 停止所有服务 |
| `restart` | 重启服务 |
| `interactive` | 交互式部署（逐步提示输入） |
| `--help, -h` | 显示帮助信息 |

## 参数说明

| 参数 | 说明 | 必填 |
|------|------|------|
| `-p, --port` | OpenCode 服务端口（默认：56780） | 否 |
| `-u, --user` | 登录用户名（默认：opencode） | 否 |
| `-P, --password` | 登录密码（**公网访问必须设置**） | **是** |
| `-t, --token` | Cloudflare Tunnel 密钥 | **是** |
| `-c, --cors` | 允许的跨域来源（可多次使用） | 否 |

## 使用示例

### 基础部署
```bash
./opencode.sh install -t eyJh... -P MySecurePassword123
```

### 自定义端口和用户名
```bash
./opencode.sh install -p 8080 -u admin -P MyPass -t eyJh...
```

### 启用 CORS（允许自定义前端访问）
```bash
./opencode.sh install -P MyPass -t eyJh... -c https://myapp.com -c http://localhost:3000
```

### 交互式部署
```bash
./opencode.sh interactive
```

## 运行前检查清单

- [ ] **Cloudflare Tunnel 密钥**：确保已获取以 `eyJh` 开头的密钥
- [ ] **端口占用**：检查默认 56780 是否被占用
  ```bash
  ss -ltnp 2>/dev/null | grep -E ":56780"
  ```
- [ ] **依赖工具**：确保已安装 curl 和 wget
- [ ] **写入权限**：确保 `~/.opencode` 目录可写（脚本自动使用当前用户目录）
- [ ] **安全性**：避免在命令行暴露明文密码，优先使用环境变量

## 日志与文件

所有文件保存在 `~/.opencode/` 目录（自动使用当前用户家目录）：

| 文件 | 说明 |
|------|------|
| `opencode.log` | OpenCode 服务日志（>10MB 自动清空） |
| `cloudflared.log` | Cloudflared 隧道日志（>10MB 自动清空） |
| `opencode.pid` | OpenCode 进程 ID（自动清理残留） |
| `cloudflared.pid` | Cloudflared 进程 ID（自动清理残留） |
| `cloudflared` | Cloudflared 可执行文件 |
| `bin/opencode` | OpenCode 可执行文件 |

## 获取 Cloudflare Tunnel 密钥

1. 登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. 进入 **Networks** → **Tunnels**
3. 创建隧道，复制以 `eyJh` 开头的 Token

**临时隧道（测试用）**：
```bash
cloudflared tunnel --url http://127.0.0.1:56780
```

## 服务管理

### 查看状态
```bash
./opencode.sh status
```

### 停止服务
```bash
./opencode.sh stop
```

### 重启服务
```bash
./opencode.sh restart -p 56780 -u opencode -P MyPass -t eyJh...
```

## 安全性与最佳实践

- **强制密码认证**：脚本要求必须设置密码，公网访问不安全
- **使用非 root 用户**：建议普通用户运行，必要时 sudo 提权
- **密码管理**：避免在命令历史暴露密码，优先使用交互模式
- **定期更新**：关注 OpenCode 和 Cloudflared 安全公告
- **日志审计**：定期查看日志文件，监控异常访问

## 常见问题

### Q: 安装失败怎么办？
- 检查网络连接
- 验证 Cloudflare Token 是否正确
- 查看日志：`tail -f ~/.opencode/opencode.log`

### Q: 端口被占用？
- 使用 `-p` 指定其他端口
- 查找占用进程：`lsof -i :56780`

### Q: Cloudflared 下载失败？
- 手动下载对应架构版本：[cloudflared releases](https://github.com/cloudflare/cloudflared/releases)
- 放置到 `~/.opencode/cloudflared` 并赋予执行权限

### Q: 如何接入自定义前端？
- 启动时添加 `-c` 参数允许跨域
- 使用 HTTP Basic Auth 连接 API

## 技术说明

### OpenCode 模式
- 当前使用 `opencode serve` 启动**无头 HTTP 服务器**
- 提供 OpenAPI 3.1 接口，适合程序化调用
- 如需 Web 界面版，可将脚本中的 `serve` 改为 `web`

### CORS 配置
- 支持多个来源，可多次使用 `-c` 参数
- 示例：`-c https://app1.com -c https://app2.com`

### PID 管理
- 启动前自动检测并清理残留 PID 文件
- 避免"幽灵进程"误判

### 日志管理
- 启动前检查日志大小
- 超过 10MB 自动清空，防止磁盘占满

## 许可证

MIT 许可证

## 参考链接

- [OpenCode 官方文档](https://docs.opencode.ai/)
- [OpenCode GitHub](https://github.com/anomalyco/opencode)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [OpenCode Server API 文档](https://opencode.ai/docs/server/)
