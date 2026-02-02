# syntax=docker/dockerfile:1.7
# 支持的发行版：
# - ubuntu:20.04 / ubuntu:22.04 / ubuntu:24.04
# - debian:10 / debian:11 / debian:12 / debian:13
FROM debian:12

# ---- 构建参数和环境变量 ----
ARG DEBIAN_FRONTEND=noninteractive
ARG TTYD_VERSION=1.7.7
ARG APP_REV=20260202-05

# libwebsockets 日志默认更安静（可在运行时用 TTYD_DEBUG 调整）
ENV LWS_LOG_LEVEL=3

# ---- 基础工具 ----
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget git vim nano htop iputils-ping net-tools sudo less tree openssh-server \
    && rm -rf /var/lib/apt/lists/*

# ---- 创建 user 用户并设置密码 ----
RUN useradd -m user 2>/dev/null || true
RUN echo 'user:user' | chpasswd 2>/dev/null || true

# ---- 免密 sudo ----
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user && chmod 0440 /etc/sudoers.d/user

# ---- 安装 ttyd (多架构) ----
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        x86_64)  TTYD_FILE="ttyd.x86_64" ;; \
        aarch64) TTYD_FILE="ttyd.aarch64" ;; \
        armv7l)  TTYD_FILE="ttyd.armhf" ;; \
        *) echo "不支持的架构: $ARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${TTYD_FILE}"; \
    chmod +x /usr/local/bin/ttyd; \
    /usr/local/bin/ttyd -v

# ---- 安装 Node.js (最新版本) ----
RUN curl -fsSL "https://deb.nodesource.com/setup_current.x" | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    node -v && npm -v

# ---- SSH 设置 ----
RUN mkdir -p /home/user/.ssh && chown -R user:user /home/user/.ssh && \
    chmod 700 /home/user/.ssh && \
    curl -fsSL -o /home/user/.ssh/authorized_keys "https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/ssh_key/id_rsa.pub" && \
    chmod 600 /home/user/.ssh/authorized_keys && \
    chown user:user /home/user/.ssh/authorized_keys

# ---- SSH 主机密钥 ----
RUN ssh-keygen -A 2>/dev/null || true

# ---- 应用文件 ----
RUN mkdir -p /home/user/app && chown -R user:user /home/user/app
WORKDIR /home/user/app
COPY --chown=user:user start.sh /usr/local/bin/start-ttyd.sh
RUN chmod +x /usr/local/bin/start-ttyd.sh

# ---- 运行时用户和工作目录 ----
USER user
WORKDIR /home/user/app

# ---- 暴露端口 ----
EXPOSE 22 7860

# ---- 健康检查 ----
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS "http://127.0.0.1:7860" >/dev/null || exit 1

# ---- 启动命令 ----
CMD ["/usr/local/bin/start-ttyd.sh"]
