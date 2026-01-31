# OpenCode + Cloudflare Tunnel 一键安装脚本
快速搭建 OpenCode 服务端并通过 Cloudflare Tunnel 暴露公网。文档按新版整理，包含运行前检查、单行执行、交互式部署、日志/状态查看、以及常见问题。

## 目录
- 快速开始
- 运行前检查（内联清单）
- 本地执行方案
- 交互式本地部署
- 日志与目录
- 服务验证（推荐）
- 获取 Cloudflare Tunnel 密钥
- 服务状态与公网地址
- 安全性与最佳实践
- 常见问题
- 许可证
- 参考与链接

## 快速开始
- 安装与启动（示例，替换 CF 密钥；可选传入公网域名用于 status 显示）：

```bash
bash -lc 'curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/main/opencode-server-cloudflared/opencode-server-cloudflared.sh -o opencode-server-cloudflared.sh && \
chmod +x opencode-server-cloudflared.sh && \
bash ./opencode-server-cloudflared.sh install -p 56780 -u opencode -P "Admin@12345678" -t YOUR_CF_TOKEN'
