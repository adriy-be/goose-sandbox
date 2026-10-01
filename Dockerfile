# Pinned by OCI digest — update via README "Upgrading base images" section.
# goose v1.52.0 → sha256:fb24feb32cf012a232da07ebb71fb50742264f2d4268fa2de9c860c34f3e5262
FROM ghcr.io/aaif-goose/goose:v1.52.0@sha256:fb24feb32cf012a232da07ebb71fb50742264f2d4268fa2de9c860c34f3e5262

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
# Pinned by OCI digest — update via README "Upgrading base images" section.
# uv 0.12.1 → sha256:cf4eedcaa81655197f625739489effcbe71b61ceb1506f332c3facae5deceded
COPY --from=ghcr.io/astral-sh/uv:0.12.1@sha256:cf4eedcaa81655197f625739489effcbe71b61ceb1506f332c3facae5deceded /uv /uvx /bin/

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
