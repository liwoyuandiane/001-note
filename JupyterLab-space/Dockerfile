FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    HOME=/root

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    wget \
    bzip2 \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

ENV CONDA_AUTO_UPDATE_CONDA=false \
    PATH=/root/miniconda/bin:$PATH

RUN curl -sLo /tmp/miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-py39_24.9.2-0-Linux-x86_64.sh \
    && chmod +x /tmp/miniconda.sh \
    && /tmp/miniconda.sh -b -p /root/miniconda \
    && rm /tmp/miniconda.sh \
    && /root/miniconda/bin/conda install -y -c conda-forge pip \
    && /root/miniconda/bin/conda clean -ya

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    git \
    wget \
    procps \
    git-lfs \
    libx11-6 \
    libsndfile-dev \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g configurable-http-proxy

RUN adduser --disabled-password --gecos '' --shell /bin/bash --uid 1000 user \
    && echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-user \
    && chmod 0440 /etc/sudoers.d/90-user

COPY --from=builder /root/miniconda /home/user/miniconda

COPY --chown=user:user requirements.txt .

RUN /home/user/miniconda/bin/python -m pip install --no-cache-dir --upgrade -r requirements.txt

USER user
WORKDIR /home/user/app

COPY --chown=user:user start_server.sh login.html .

RUN chmod +x start_server.sh

ENV HOME=/home/user \
    CONDA_AUTO_UPDATE_CONDA=false \
    PATH=/home/user/miniconda/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    SYSTEM=spaces \
    SHELL=/bin/bash \
    LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS "http://127.0.0.1:7860" >/dev/null 2>&1 || exit 1

CMD ["./start_server.sh"]
