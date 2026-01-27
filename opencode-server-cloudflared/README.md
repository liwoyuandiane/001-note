# OpenCode + Cloudflare Tunnel 一键安装脚本

快速搭建 OpenCode 服务端并通过 Cloudflare Tunnel 暴露公网。文档按新排版整理，包含内联运行前检查、单行执行、交互式部署等清晰入口。

## 目录
- 快速开始
- 运行前检查（内联清单）
- 本地执行方案
- 交互式本地部署
- 日志与目录
- 获取 Cloudflare Tunnel 密钥
- 服务状态与公网地址
- 安全性与最佳实践
- 常见问题
- 许可证
- 参考与链接

## 快速开始
- 安装与启动（示例，替换 CF 密钥）：
```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && \
chmod +x opencode.sh && \
bash ./opencode.sh install -t YOUR_CF_TOKEN -p 56780 -u opencode -P "Admin@12345678"'
```
- 从本地保存后执行（单行命令）：
```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && \
chmod +x opencode.sh && \
bash ./opencode.sh install -t YOUR_CF_TOKEN -p 56780 -u opencode -P "Admin@12345678"'
```
- 仅用于离线下载的单行版本请参考文件内的内联清单。

## 运行前检查（内联清单）
- Cloudflare Tunnel 密钥 token：确保已获取并能通过 -t/--token 指定。
- 端口占用情况：默认 56780，请确保端口未被占用；必要时使用 -p 指定端口。
- 依赖就绪：确保系统已安装 curl 或 wget。
- OpenCode 路径与写权限：确保 ~/.opencode 及子目录可写，日志与 PID 文件可写。
- 日志与写权限：确保日志目录可写，便于诊断。
- 安全性：避免在命令行暴露明文密码，优先使用 -P 或环境变量注入。
- 离线/替代方案：若网络受限，准备离线的 cloudflared 二进制并放置在 ~/.opencode/cloudflared。
- 验证安装：安装完成后执行 status，检查运行状态与日志。
- 回滚与清理：安装失败时执行 stop，清理相关 PID 与日志。

- 快速检查命令示例：
- ss 与 netstat 的端口检查示例（请把 56780 替换为实际端口）：
```bash
ss -ltnp 2>/dev/null | grep -E ":56780[[:space:]]"
```
```bash
netstat -tlnp 2>/dev/null | grep -E ":56780[[:space:]]" 
```

- 依赖性与权限示例：
```bash
cURL --version
wget --version
mkdir -p ~/.opencode
touch ~/.opencode/test
```

## 本地执行方案
- 直接下载本地脚本并执行（非交互）如下：
```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && chmod +x opencode.sh && bash ./opencode.sh install -t YOUR_CF_TOKEN -p 56780 -u opencode -P "Admin@12345678"'
```
- 交互式本地部署（单行命令）如下：
```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode.sh && chmod +x opencode.sh && bash ./opencode.sh interactive'
```

## 交互式本地部署（新增）
- 脚本会逐步提示你输入：端口、用户名、密码、CF 密钥等。
- 输入完成后脚本将自动开始部署。

## 日志与目录
- 日志与 PID 文件保存在 ~/.opencode/ 目录下
- OpenCode 日志：~/.opencode/opencode.log
- Cloudflared 日志：~/.opencode/cloudflared.log
- OpenCode_pid：~/.opencode/opencode.pid
- Cloudflared_pid：~/.opencode/cloudflared.pid

## 获取 Cloudflare Tunnel 密钥
- 进入 Cloudflare Zero Trust 控制台创建隧道，获取以 eyJh 开头的密钥。
- 如需临时隧道，也可使用 Quick Tunnel：
```
cloudflared tunnel --url http://localhost:56780
```

## 服务状态与公网地址
- 启动成功后，脚本会输出公网访问地址（随隧道状态而定）。
- 使用 status 命令查看运行状态。

## 安全性与最佳实践
- 使用非 root 用户运行，必要时通过 sudo 提权。
- 不要在命令行直接暴露密码，优先通过 -P 或环境变量注入。
- 定期更新脚本与 cloudflared，关注安全公告。

## 常见问题
- 安装失败：检查网络、端口占用、隧道密钥是否正确。
- cloudflared 下载失败：可手动下载并放置在 ~/.opencode/cloudflared；确保可执行权限。
- 生产环境：尽量在测试环境验证后再投入生产。

## 许可证
- MIT 许可证。

## 参考与链接
- OpenCode 官方文档：https://docs.opencode.ai/
- OpenCode GitHub：https://github.com/anomalyco/opencode
- Cloudflare Tunnel 文档：https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
