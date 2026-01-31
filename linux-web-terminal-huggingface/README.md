---
title: Ubuntu Web Terminal (ttyd)
emoji: 🖥️
colorFrom: blue
colorTo: gray
sdk: docker
app_port: 7860
---

# Ubuntu Web Terminal (ttyd) for Hugging Face Spaces

一个基于 **Ubuntu 22.04** 的 Web 终端，使用 **ttyd** 提供浏览器访问，适配 **Hugging Face Spaces（Docker SDK）**。

## 特性

- ✅ **Hugging Face Spaces 兼容**：容器按官方建议使用 **UID=1000** 的非 root 用户运行，减少权限问题。
- 🔐 **访问控制**：通过 `TTYD_CREDENTIAL` 开启 HTTP Basic Auth。
- 🔓 **免密 sudo**：容器内 `user` 账号支持 `sudo` **无需密码**（NOPASSWD）。
- 🧘 **更安静的日志**：默认 `TTYD_DEBUG=3`（仅 ERR+WARN），减少 `N: __lws_*` 这类 NOTICE 刷屏。
- 🧰 常用工具：vim / nano / git / htop / ping / net-tools / tree 等。

> ⚠️ 安全提醒：免密 sudo + Web 终端意味着一旦凭据泄露，攻击者可能获得容器内 root 权限。请使用强密码并定期更换。

---

## 目录结构

仓库根目录应包含：

- `Dockerfile`
- `start.sh`
- `README.md`

（不要只上传 zip；Spaces 不会自动解压。）

---

## 部署到 Hugging Face Spaces

1. 新建 Space，选择 **Docker** 作为 SDK。
2. 上传本仓库 3 个文件到 Space 根目录并 Commit。
3. 在 Space 页面 **Settings → Variables and secrets** 设置环境变量：

### 必填变量

- `TTYD_CREDENTIAL`：格式 `用户名:密码`
  - 示例：`admin:MySecurePassword123!`

### 可选变量

- `TTYD_DEBUG`：ttyd 日志级别（bitmask）
  - 默认：`3`（ERR+WARN，推荐）
  - 排障：`7`（ERR+WARN+NOTICE）
  - 更详细：`15`（再加 INFO）
- `HOME`：工作目录（默认 `/home/user/work`）
- `URL_SH`：启动后下载并执行的脚本 URL
- `SCRIPT_ARGS`：传给脚本的参数

> 说明：HTTP Basic Auth 在浏览器端可能会被缓存，所以你可能不会每次都看到弹窗；使用无痕窗口或更换设备可验证。

---

## 使用说明

- 打开 Space 的 App 页面，即可进入 Web 终端。
- 免密 sudo 示例：

```bash
sudo -i
sudo apt-get update
```

---

## 本地运行（可选）

```bash
docker build -t hf-ttyd .
docker run --rm -p 7860:7860 -e TTYD_CREDENTIAL=admin:pass hf-ttyd
```

然后访问 `http://localhost:7860`。

---

## 参考

- Hugging Face Docker Spaces：端口 7860、以及容器以 UID 1000 运行等注意事项。
- ttyd 参数说明：`-d` 设置日志级别，`-q` 为 `--exit-no-conn`（不要用）。
- libwebsockets 日志位：ERR/WARN/NOTICE/INFO 等是 bitmask 组合。

---

## License

MIT
