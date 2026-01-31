FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    wget \
    bzip2 \
    && rm -rf /var/lib/apt/lists/*

ENV CONDA_AUTO_UPDATE_CONDA=false \
    PATH=$HOME/miniconda/bin:$PATH

RUN curl -sLo ~/miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-py39_24.9.2-0-Linux-x86_64.sh \
    && chmod +x ~/miniconda.sh \
    && ~/miniconda.sh -b -p ~/miniconda \
    && rm ~/miniconda.sh \
    && conda clean -ya

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    HOME=/home/user \
    CONDA_AUTO_UPDATE_CONDA=false \
    PATH=$HOME/miniconda/bin:$PATH

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
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g configurable-http-proxy

RUN adduser --disabled-password --gecos '' --shell /bin/bash --uid 1000 user \
    && echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-user \
    && chmod 0440 /etc/sudoers.d/90-user

USER user
WORKDIR $HOME/app

COPY --from=builder /root/miniconda $HOME/miniconda

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS "http://127.0.0.1:7860" >/dev/null || exit 1

RUN mkdir $HOME/.cache $HOME/.config \
    && chmod -R 777 $HOME

COPY --chown=user requirements.txt .

RUN pip install --no-cache-dir --upgrade -r requirements.txt

COPY --chown=user start_server.sh login.html .
RUN chmod +x start_server.sh && \
    JUPYTER_PATH=$(python3 -c "import jupyter_server, os; print(os.path.dirname(jupyter_server.__file__))"); \
    mkdir -p "$JUPYTER_PATH/templates"; \
    cp login.html "$JUPYTER_PATH/templates/login.html"

ENV PYTHONUNBUFFERED=1 \
    SYSTEM=spaces \
    SHELL=/bin/bash \
    LABEL maintainer="JupyterLab Space"

CMD ["./start_server.sh"]
