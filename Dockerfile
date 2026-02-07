FROM pytorch/pytorch:2.10.0-cuda12.8-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV UV_LINK_MODE=copy
ENV UV_CACHE_DIR="/root/.cache/uv"
ENV PATH="/root/.local/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    curl \
    openssh-server \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install uv (pre-install for cache)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /workspace

# Copy entire repo
ARG CACHEBUST=1
COPY . .

# Setup SSHd
RUN mkdir -p /run/sshd && \
    sed -i 's/^#\?PermitRootLogin .*$/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication .*$/PasswordAuthentication no/' /etc/ssh/sshd_config

# Setup Filebrowser
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Run Install Script
ENV ACC_CHOICE=2
ENV CLONE_REPLY=Y
ENV ACE_STEP_REPO_PATH=/workspace/ACE-Step-1.5

RUN --mount=type=cache,target=/root/.cache/uv \
    chmod +x scripts/install.sh && \
    ./scripts/install.sh --system

# Environment Variables for Runtime
ENV HF_HOME="/workspace/models"
ENV TORCH_HOME="/workspace/models"

RUN chmod +x run.sh entrypoint.sh

EXPOSE 8788 5175 8080 22

ENTRYPOINT ["/workspace/entrypoint.sh"]
CMD ["/bin/bash", "/workspace/run.sh"]
