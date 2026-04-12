# AGENTS.md

## HuggingFace Space

- **Type**: Docker Space (node:18-slim)
- **Port**: 7860
- **Host**: 0.0.0.0

## Environment Secrets (required)

Set in Space Settings → Secrets and variables:

| Secret | Usage |
|--------|-------|
| `HF_TOKEN` | HuggingFace API token for bucket sync |
| `HF_SPACE` | Space name (e.g., `jerecom/opencode-xxx`) for bucket sync |
| `OPENCODE_SERVER_USERNAME` | OpenCode web UI login username |
| `OPENCODE_SERVER_PASSWORD` | OpenCode web UI login password |

## Runtime Flow

1. **STEP -1**: Create bucket (if not exists) named after current Space
2. **STEP 0**: Restore from bucket → `/home`
3. **STEP 1**: Start OpenCode (14GB RAM limit, auto-restart on OOM)
4. **STEP 2**: Watch filesystem with inotify, sync back to bucket (30s debounce)

## Key Files

- `/home` - User workspace (synced to bucket)
- `/home/.opencode/logs` - Persistent logs (opencode.log, entrypoint.log)
- `/entrypoint.sh` - Startup orchestration
- `/Dockerfile` - Container definition
- **BUCKET**: `hf://buckets/{space-id}/home` (保持完整路径)

## Sync Exclusions

```bash
--exclude "*.mdb,*.log,*/.cache/*,*/.npm/*,.check_for_update_done,rg,*/.local/*,*/.opencode/*"
```

## Development Notes

- Logs moved to persistent directory `/home/.opencode/logs` - survives container restart
- Entrypoint log uploaded only once (tracked by `entrypoint-uploaded` flag file)
- All exclusion patterns unified between hf sync and inotifywait