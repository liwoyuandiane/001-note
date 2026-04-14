FROM node:18-slim

# 安装系统工具和 HF CLI
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    git \
    python3 \
    python3-pip \
    python3.11-venv \
    procps \
    iputils-ping \
    nano \
    vim \
    telnet \
    net-tools \
    wget \
    rsync \
    && curl -LsSf https://hf.co/cli/install.sh | bash \
    && rm -rf /var/lib/apt/lists/*

# 安装 OpenCode
RUN npm i -g opencode-ai

# 创建目录
RUN mkdir -p /home && chmod 777 /home

# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 环境设置
ENV PATH="/root/.local/bin:/home/node/.local/bin:/home/.local/bin:$PATH"
ENV NODE_OPTIONS="--max-old-space-size=14336"

EXPOSE 7860
CMD ["/entrypoint.sh"]