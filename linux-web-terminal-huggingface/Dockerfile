# Debian Web Terminal - Dockerfile
# 基于 Ubuntu 22.04（工具更丰富），使用 ttyd 提供 Web 访问

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LWS_LOG_TIMESTAMP=0
ENV LWS_LOG_TAG=0
ENV LWS_LOG_LEVEL=3
ENV LWS_LOG_UUID=0
ENV LWS_LOG_LATENCY=0
ENV LWS_LOG_HDRS=0
ENV LWS_LOG_EXT=0

RUN apt update && apt upgrade -y \
    && apt install -y curl wget git vim nano htop iputils-ping net-tools sudo less tree \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        TTYD_FILE="ttyd.x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        TTYD_FILE="ttyd.aarch64"; \
    else \
        echo "不支持的架构: $ARCH"; \
        exit 1; \
    fi && \
    curl -L -o /tmp/ttyd "https://github.com/tsl0922/ttyd/releases/download/1.7.7/${TTYD_FILE}" \
    && chmod +x /tmp/ttyd \
    && mv /tmp/ttyd /usr/local/bin/ttyd

RUN curl -L -o /usr/local/bin/start-ttyd.sh \
    https://huggingface.co/spaces/wwdasaftgw/de-bi-an/raw/main/start.sh \
    && chmod +x /usr/local/bin/start-ttyd.sh

EXPOSE 7860

CMD ["/usr/local/bin/start-ttyd.sh"]
