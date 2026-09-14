FROM ghcr.io/aaif-goose/goose:v1.50.0

USER root

# -------------------------------------------------------------------
# Base agent tools (common to every sandbox)
# Toolchains (C/C++, embedded, C#, server...) live in project recipes,
# not in this base image. See recipes/ for ready-made examples.
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
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
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
