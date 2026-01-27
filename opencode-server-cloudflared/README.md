# OpenCode + Cloudflare Tunnel 一键安装脚本


本脚本在 Linux 服务器上实现一键安装 OpenCode 服务端，并通过 Cloudflare Tunnel 将端口暴露到公网。此 README 对内容进行重构，提升语言表达和结构可读性。

## 适用场景
- 快速在服务器上部署 OpenCode 服务端，方便远程接入和协作。
- 通过 Cloudflare Tunnel 实现公网访问，无需暴露本地端口。

## 依赖与前提
- Linux 发行版（推荐 Ubuntu/Debian、RHEL/CentOS）及 x86_64/ARM64 架构。
- 拥有具备 sudo 权限的用户，避免以 root 长期运行任务。
- 服务器具备网络访问能力，能够下载 OpenCode 安装脚本与 cloudflared。
- 需要 Cloudflare Tunnel 的密钥 token（安装时必须提供）。

## 快速开始

### 安装与启动（示例）
- 替换下面命令中的 token，执行即可完成安装并启动：
```
bash <(curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh) install -t <token>
```
- 支持使用密码，密码参数为 -P。

### 自定义参数
- -p, --port: OpenCode 服务端口，默认 56780
- -u, --user: 登录用户名，默认 opencode
- -P, --password: 登录密码，默认无（无密码）
- -t, --token: Cloudflare Tunnel 密钥，必填

### 常用用法
- 查看帮助：bash ./opencode-server-cloudflared.sh --help
- 查看状态：bash ./opencode-server-cloudflared.sh status
- 停止服务：bash ./opencode-server-cloudflared.sh stop
- 重启服务：bash ./opencode-server-cloudflared.sh restart

## 日志与目录
- 日志与 PID 文件保存在 ~/.opencode/ 目录下
- opencode.log、cloudflared.log（日志文件路径）
- opencode.pid、cloudflared.pid（进程 ID 文件）

## 获取 Cloudflare Tunnel 密钥
- 前往 Cloudflare Zero Trust 控制台创建隧道，获取以 eyJh 开头的密钥。
- 也可使用 Quick Tunnel（临时隧道，不需要密钥）:
```
cloudflared tunnel --url http://localhost:56780
```

## 服务状态与公网地址
- 启动成功后，脚本会输出公网访问地址，例如 https://xxxx.trycloudflare.com（视 Cloudflare 隧道状态而定）。
- 通过 status 命令查看运行状态。

## 安全性与最佳实践
- 尽量以非 root 用户运行，必要时通过 sudo 提权。
- 不要在命令行直接暴露敏感信息，优先使用环境变量或配置文件传递密码/密钥。
- 定期更新脚本与 cloudflared，关注安全公告。

## 常见问题
- 安装失败：请检查网络、端口占用、以及隧道密钥是否正确。
- cloudflared 下载失败：可手动下载并放置在 ~/.opencode/cloudflared；确保可执行权。
- 生产环境建议：在测试环境验证后再投入生产。

## 许可证
- MIT 许可证。

## 参考与链接
- OpenCode 官方文档：https://docs.opencode.ai/
- OpenCode GitHub：https://github.com/anomalyco/opencode
- Cloudflare Tunnel 文档：https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

## 运行前检查（内联清单）
- Cloudflare Tunnel 密钥 token：确保已获取并能通过 -t/--token 指定。安装命令示例：bash opencode-server-cloudflared.sh install -t <token>
- 端口占用情况：要暴露的端口默认 56780，请确保端口未被占用；如需使用其他端口，传入 -p/--port。
  验证方法示例：
  - ss -ltnp 2>/dev/null | grep -E ":56780[[:space:]]"
  - netstat -tlnp 2>/dev/null | grep -E ":56780[[:space:]]"
- 依赖就绪：确保系统具备 curl 或 wget；可通过 curl --version / wget --version 验证。
- OpenCode 路径与写权限：确保 ~/.opencode 及子目录可写，以便日志与 PID 文件写入。
- 日志与写权限：确认日志目录可写，避免写入失败导致无法诊断。
- 安全性：尽量避免在命令行暴露明文密码，使用 -P 或通过环境变量/配置传入敏感信息。
- 离线/替代方案：若服务器无法访问网络，可准备离线的 cloudflared 二进制并放置于 ~/.opencode/cloudflared，确保可执行权限。
- 验证安装：安装完成后执行 status，查看 OpenCode 与 Cloudflared 的运行状态及日志。
- 回滚与清理：如果安装失败，执行 stop，清理相关 PID 文件与日志目录，恢复初始状态。
