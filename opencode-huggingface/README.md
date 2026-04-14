---
title: opencode-ai
emoji: 🐢
colorFrom: pink
colorTo: gray
sdk: docker
pinned: false
---

## 环境变量

在 Space Settings → Secrets and variables 中设置：

| 变量 | 必填 | 说明 |
|------|------|------|
| `OPENCODE_SERVER_USERNAME` | 是 | OpenCode web UI 登录用户名 |
| `OPENCODE_SERVER_PASSWORD` | 是 | OpenCode web UI 登录密码 |
| `LOG_LEVEL` | 否 | 日志级别：`debug`/`info`/`warning`（默认：warning） |

## 持久化存储

**重要**：需要将 HuggingFace bucket 挂载到 `/root` 目录作为持久化存储。

在 Space Settings → Repo 中：
- 将 Persistent Storage 路径设置为 `/root`

这样所有数据（用户文件、日志等）都会直接持久化到 bucket，无需额外备份。

## 功能特性

- 运行在 HuggingFace Spaces 上的 OpenCode AI 助手
- 数据持久化到 bucket（/root 目录）
- RAM 监控，内存超限时自动重启（14GB 限制）