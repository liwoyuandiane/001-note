# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04

# ---- 构建参数和环境变量 ----
ARG DEBIAN_FRONTEND=noninteractive
ARG TTYD_VERSION=1.7.7
# 用于强制触发 Docker 构建缓存失效（需要强制重建时改这个值）
ARG APP_REV=20260130-03

# libwebsockets 日志默认更安静（可在运行时用 TTYD_DEBUG 调整）
ENV LWS_LOG_LEVEL=3

# ---- Create non-root user for HF Spaces (UID=1000) ----
# Hugging Face Spaces 容器以 uid=1000 运行，建议创建该用户并在 COPY/下载前设置 WORKDIR
RUN useradd -m -u 1000 user && echo "user:user" | chpasswd

# ---- Base tools (minimal) ----
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl wget git vim nano htop iputils-ping net-tools sudo less tree openssh-server \
  && rm -rf /var/lib/apt/lists/*

# ---- Passwordless sudo for user (NOPASSWD) ----
# 通过 /etc/sudoers.d 添加免密 sudo（文件权限必须是 0440）
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
 && chmod 0440 /etc/sudoers.d/user

# ---- 安装 ttyd (多架构) ----
RUN set -eux; \
  ARCH="$(uname -m)"; \
  case "$ARCH" in \
    x86_64)  TTYD_FILE="ttyd.x86_64" ;; \
    aarch64) TTYD_FILE="ttyd.aarch64" ;; \
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${TTYD_FILE}"; \
  chmod +x /usr/local/bin/ttyd; \
  /usr/local/bin/ttyd -v

# ---- 安装 Node.js (最新版本，多架构) ----
RUN set -eux; \
  ARCH="$(uname -m)"; \
  NODE_ARCH="$ARCH"; \
  case "$ARCH" in \
    x86_64)  NODE_ARCH="x64" ;; \
    aarch64) NODE_ARCH="arm64" ;; \
    armv7l)  NODE_ARCH="armv7l" ;; \
    armv6l)  NODE_ARCH="armv6l" ;; \
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://deb.nodesource.com/setup_current.x" | bash -; \
  apt-get install -y --no-install-recommends nodejs; \
  node -v; \
  npm -v

# ---- SSH 设置 ----
RUN mkdir -p /home/user/.ssh && chown -R user:user /home/user/.ssh \
  && chmod 700 /home/user/.ssh \
  && curl -fsSL -o /home/user/.ssh/authorized_keys "https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/ssh_key/id_rsa.pub" \
  && chmod 600 /home/user/.ssh/authorized_keys \
  && chown user:user /home/user/.ssh/authorized_keys

# ---- SSH 主机密钥 ----
RUN ssh-keygen -A 2>/dev/null || true

# ---- 暴露 SSH 端口 ----
EXPOSE 22

# ---- 应用文件 ----
RUN mkdir -p /home/user/app && chown -R user:user /home/user/app
WORKDIR /home/user/app
COPY --chown=user:user start.sh /usr/local/bin/start-ttyd.sh
RUN chmod +x /usr/local/bin/start-ttyd.sh

# ---- 运行时用户和工作目录 ----
USER user
WORKDIR /home/user/app

# ---- 暴露 HF Spaces 端口 ----
EXPOSE 7860

# ---- 健康检查 ----
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS "http://127.0.0.1:7860" >/dev/null || exit 1

# ---- 启动命令 ----
CMD ["/usr/local/bin/start-ttyd.sh"]