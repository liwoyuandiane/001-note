# JupyterLab for Hugging Face Spaces

基于 Ubuntu 22.04 的 JupyterLab Docker 镜像，专为 Hugging Face Spaces 设计。

## 功能特性

- **JupyterLab 4.x** - 交互式 Python 开发环境
- **多阶段构建** - 优化镜像体积
- **GPU 支持** - 预留 CUDA 环境配置
- **自动生成 Token** - 默认生成 32 位安全随机 token
- **灵活配置** - 支持自定义工作目录和启动脚本
- **安全加固** - XSRF 保护、CSP 策略、sudo 免密

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `JUPYTER_TOKEN` | Jupyter 访问 token | 自动生成 32 位随机字符串 |
| `HOME_DIR` | 工作目录 | `/home/user/work` |
| `URL_SH` | 启动后下载并执行的脚本 URL | 无 |
| `SCRIPT_ARGS` | 传给脚本的参数 | 无 |

## 使用方法

### 1. 基础部署（仅 JupyterLab）

```bash
docker build -t jupyterlab-space .
docker run -p 7860:7860 jupyterlab-space
```

### 2. 自定义 Token

```bash
docker run -e JUPYTER_TOKEN=my_secret_token -p 7860:7860 jupyterlab-space
```

### 3. 自定义工作目录

```bash
docker run -e HOME_DIR=/data -p 7860:7860 jupyterlab-space
```

### 4. 启动后执行脚本

```bash
docker run -e URL_SH="https://example.com/setup.sh" -p 7860:7860 jupyterlab-space
```

### 5. 带参数执行脚本

```bash
docker run -e URL_SH="https://example.com/setup.sh" -e SCRIPT_ARGS="--install-deps" -p 7860:7860 jupyterlab-space
```

## Hugging Face Spaces 配置

### 在 Spaces 中使用

1. 创建新的 Space，选择 **Docker** 类型
2. 复制本仓库文件到你的 Space 仓库
3. Space 会自动构建并部署

### 设置环境变量

在 Hugging Face Spaces 的 **Settings → Variables and secrets** 中添加：

- `JUPYTER_TOKEN` - 自定义访问 token（可选）
- `HOME_DIR` - 工作目录（可选）
- `URL_SH` - 启动脚本 URL（可选）
- `SCRIPT_ARGS` - 脚本参数（可选）

## 项目结构

```
├── Dockerfile           # Docker 构建文件
├── start_server.sh      # 启动脚本
├── login.html           # 自定义登录页面
├── requirements.txt     # Python 依赖
├── .dockerignore        # Docker 构建忽略文件
└── README.md            # 中文文档
```

## 镜像规格

- **基础镜像**: Ubuntu 22.04
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

```bash
# 检查日志
docker logs <container_id>
```

### 端口占用

修改默认端口：
```bash
docker run -p <your_port>:7860 jupyterlab-space
```

### Token 忘记

设置新 token：
```bash
docker run -e JUPYTER_TOKEN=new_token -p 7860:7860 jupyterlab-space
```

## 构建命令

```bash
# 本地构建
docker build -t jupyterlab-space .

# 构建多平台镜像
docker buildx build --platform linux/amd64,linux/arm64 -t jupyterlab-space .
```

## License

MIT License
