# 1. Node.js 稳定版
FROM node:18-slim


# 2. 安装所需系统工具和 HF CLI
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    git \
    python3 \
    python3-pip \
    python3.11-venv \
    build-essential \
    gcc \
    g++ \
    make \
    nano \
    zip \
    unzip \
    procps \
    inotify-tools \
    iputils-ping \
    vim \
    telnet \
    net-tools \
    wget \
    && curl -LsSf https://hf.co/cli/install.sh | bash \
    && rm -rf /var/lib/apt/lists/*


# 3. 安装 OpenCode
RUN curl -fsSL https://opencode.ai/install | bash


# 4. 创建目录
RUN mkdir -p /home && chmod 777 /home


# 5. 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh


# 6. 环境设置（带 RAM 限制）
ENV OPENCODE_DATA_DIR=/home
ENV HOME=/home
ENV PATH="/root/.local/bin:/home/node/.local/bin:/home/.local/bin:$PATH"
ENV NODE_OPTIONS="--max-old-space-size=14336"


# 7. 暴露端口 7860
EXPOSE 7860


# 8. 运行入口脚本
CMD ["/entrypoint.sh"]