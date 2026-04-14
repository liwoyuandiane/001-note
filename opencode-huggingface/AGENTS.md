# AGENTS.md

## HuggingFace Space

- **Type**: Docker Space (node:18-slim)
- **Port**: 7860
- **Host**: 0.0.0.0

## Environment Secrets (required)

Set in Space Settings → Secrets and variables:

| Secret | Usage |
|--------|-------|
| `OPENCODE_SERVER_USERNAME` | OpenCode web UI login username |
| `OPENCODE_SERVER_PASSWORD` | OpenCode web UI login password |
| `LOG_LEVEL` | Logging level: `debug`/`info`/`warning` (optional, default: warning) |

## Persistent Storage

**Important**: Need to mount HuggingFace bucket to `/root` directory for persistent storage.

In Space Settings → Repo:
- Set Persistent Storage path to `/root`

## Runtime Flow

1. 设置 DNS（运行时）
2. 创建日志目录 `/root/.opencode/logs`
3. 启动 OpenCode（带 RAM 监控，14GB 限制）
4. 监控 OpenCode 进程，异常退出时自动重启

## Key Files

- `/root` - HuggingFace bucket 挂载目录（持久化存储）
- `/root/.opencode/logs` - 日志目录
- `/entrypoint.sh` - 启动脚本
- `/Dockerfile` - 容器定义

## Log Level

| LOG_LEVEL | 效果 |
|-----------|------|
| `warning`（默认） | 只显示 warning/error |
| `info` | + info 日志 |
| `debug` | + 详细调试信息（RAM 使用率） |

## Log Rotation

- 日志文件超过 100MB 自动轮转
- 轮转后的日志文件保存为 `entrypoint-YYYY-MM-DD.log`

## Development Notes

- 数据持久化：`/root` 由 HuggingFace bucket 挂载
- 日志位置：`/root/.opencode/logs/`
- RAM 限制：14GB，超限自动重启