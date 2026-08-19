FROM ghcr.io/aaif-goose/goose:v1.36.0

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
# uv (pinned, copied from the official image)
# -------------------------------------------------------------------
COPY --from=ghcr.io/astral-sh/uv:0.12.1 /uv /uvx /bin/

# -------------------------------------------------------------------
# Workspace + persistent Goose state
# -------------------------------------------------------------------
RUN mkdir -p /workspace /goose-state \
    && chown goose:goose /workspace /goose-state

USER goose
WORKDIR /workspace

# /goose-state is bind-mounted by the launcher from
# <project>/.goose-sandbox. Keeping it outside /workspace prevents Goose
# from treating its own state as project source during normal analysis.
ENV GOOSE_PATH_ROOT=/goose-state

ENTRYPOINT ["goose"]
CMD ["session"]
