# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04

# ---- Build args & envs ----
ARG DEBIAN_FRONTEND=noninteractive
ARG TTYD_VERSION=1.7.7
# 用于强制触发 Docker 构建缓存失效（需要强制重建时改这个值）
ARG APP_REV=20260130-03

# libwebsockets 日志默认更安静（可在运行时用 TTYD_DEBUG 调整）
ENV LWS_LOG_LEVEL=3

# ---- Create non-root user for HF Spaces (UID=1000) ----
# Hugging Face Spaces 容器以 uid=1000 运行，建议创建该用户并在 COPY/下载前设置 WORKDIR
RUN useradd -m -u 1000 user

# ---- Base tools (minimal) ----
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git vim nano htop iputils-ping net-tools sudo less tree \
 && rm -rf /var/lib/apt/lists/*

# ---- Passwordless sudo for user (NOPASSWD) ----
# 通过 /etc/sudoers.d 添加免密 sudo（文件权限必须是 0440）
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
 && chmod 0440 /etc/sudoers.d/user

# ---- Install ttyd (multi-arch) ----
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

# ---- App files ----
WORKDIR /home/user/app
COPY --chown=user:user start.sh /usr/local/bin/start-ttyd.sh
RUN chmod +x /usr/local/bin/start-ttyd.sh

# ---- Runtime user & workdir ----
USER user
WORKDIR /home/user/app

# ---- Expose HF Spaces port ----
EXPOSE 7860

# ---- Healthcheck ----
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS "http://127.0.0.1:7860" >/dev/null || exit 1

# ---- Cmd ----
CMD ["/usr/local/bin/start-ttyd.sh"]
