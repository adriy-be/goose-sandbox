FROM ghcr.io/aaif-goose/goose:latest

USER root

# -------------------------------------------------------------------
# Basic development / agent tools
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    curl \
    wget \
    ca-certificates \
    jq \
    ripgrep \
    fd-find \
    tree \
    unzip \
    zip \
    build-essential \
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    # -------------------------------------------------------------------\
    # Embedded C development tools\
    # -------------------------------------------------------------------\
    gcc \
    g++ \
    gdb \
    gdb-multiarch \
    make \
    ninja-build \
    binutils \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    libnewlib-arm-none-eabi \
    openocd \
    picocom \
    minicom \
    screen \
    usbutils \
    avrdude \
    gcc-avr \
    binutils-avr \
    avr-libc \
    stlink-tools \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# uv
# -------------------------------------------------------------------
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin sh

# -------------------------------------------------------------------
# Workspace
# -------------------------------------------------------------------
RUN mkdir -p /workspace \
    && chown goose:goose /workspace

USER goose

WORKDIR /workspace

ENV GOOSE_PATH_ROOT=/workspace/.goose-sandbox

ENTRYPOINT ["goose"]
CMD ["session"]