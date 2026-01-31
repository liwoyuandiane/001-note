---
title: JupyterLab
emoji: 💻
colorFrom: gray
colorTo: green
sdk: docker
sdk_version: "4.2.5"
python_version: "3.9"
pinned: false
tags:
  - jupyterlab
  - python
  - notebook
  - datascience
---

# JupyterLab for Hugging Face Spaces

基于 Ubuntu 22.04 的 JupyterLab Docker 镜像，专为 Hugging Face Spaces 设计。

## 功能特性

- **JupyterLab 4.2.5** - 交互式 Python 开发环境（中文界面）
- **多阶段构建** - 优化镜像体积
- **GPU 支持** - 预留 CUDA 环境配置
- **Token** - 默认 `huggingface`
- **灵活配置** - 支持自定义工作目录和启动脚本
- **安全加固** - XSRF 保护、CSP 策略、sudo 免密
- **中文支持** - 默认中文界面

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `JUPYTER_TOKEN` | Jupyter 访问 token | `huggingface` |
| `HOME` | 工作目录 | `/data` |
| `URL_SH` | 启动后下载并执行的脚本 URL | 无 |
| `SCRIPT_ARGS` | 传给脚本的参数 | 无 |
| `JUPYTERLOB` | JupyterLab 启动模式：`1`=自动启动，`0`=手动启动 | `1` |
| `LANG` | 语言设置 | `zh_CN.UTF-8` |
| `LC_ALL` | 语言设置 | `zh_CN.UTF-8` |

## 使用方法

### 1. 基础部署（仅 JupyterLab）

Space 会自动构建并部署。

### 2. 自定义 Token

在 **Settings → Variables and secrets** 中添加：
- `JUPYTER_TOKEN` - 自定义访问 token（可选）

### 3. 自定义工作目录

在 **Settings → Variables and secrets** 中添加：
- `HOME` - 工作目录（可选）

### 4. 启动后执行脚本

在 **Settings → Variables and secrets** 中添加：
- `URL_SH` - 启动脚本 URL（可选）- JupyterLab 启动后 5 秒在后台下载并执行
- `SCRIPT_ARGS` - 脚本参数（可选）- 传递给脚本的参数
- `HOME` - 工作目录（可选）- 脚本将在此目录下执行

脚本执行流程：
1. JupyterLab 启动成功后
2. 等待 5 秒
3. 在后台下载并执行 `URL_SH` 指定的脚本
4. 在后台执行工作目录下所有 `.sh` 脚本

### 5. 手动启动 JupyterLab 模式

在 **Settings → Variables and secrets** 中添加：
- `JUPYTERLOB=0` - 设置为手动启动模式

启用后：
- 容器启动后 JupyterLab **不会**自动启动
- 自动生成 `start_jupyter.sh` 辅助启动脚本
- 用户可以执行 `bash /home/user/app/start_jupyter.sh` 手动启动
- 后台脚本仍会在 5 秒后执行

### 6. 自动启动 JupyterLab 模式（默认）

- 不设置或设置 `JUPYTERLOB=1` - JupyterLab 随容器自动启动
- 这是默认行为

### 7. 语言设置

JupyterLab 默认使用中文界面。如需切换语言：
1. 打开 JupyterLab 设置
2. 选择 Language 为其他语言

## 故障排除

## 项目结构

```
├── Dockerfile           # Docker 构建文件
├── start_server.sh      # 启动脚本
├── login.html           # 自定义登录页面
├── requirements.txt     # Python 依赖
├── .dockerignore        # Docker 构建忽略文件
└── README.md            # 项目文档
```

## 镜像规格

- **基础镜像**: NVIDIA CUDA 12.5.1 + Ubuntu 20.04
- **Python 版本**: 3.9 (Miniconda)
- **Node.js 版本**: 20.x
- **JupyterLab 版本**: 4.2.5
- **默认端口**: 7860
- **默认用户**: user (UID 1000)
- **镜像大小**: ~2.5 GB

## 安全说明

- Token 默认自动生成，安全性高
- XSRF 保护已启用
- CSP 策略限制 iframe 嵌入来源
- 用户具有 sudo 免密权限

## 故障排除

### 容器无法启动

在 Space 页面查看 **Logs**。

### Token 忘记

重新设置环境变量 `JUPYTER_TOKEN`。

## License

MIT License

---

参考: [Hugging Face Spaces 配置文档](https://huggingface.co/docs/hub/spaces-config-reference)
