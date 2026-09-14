# Server management tooling (SSH, sync, diagnostics, terminals).
#
# Copy this file (and optionally its skills/ + mcp.txt) into a project as
#   .goose-sandbox/recipe/Dockerfile
# or set GOOSE_SANDBOX_RECIPE to point at it. Builds on top of the base
# image `goose-agent` (built from the root Dockerfile).

FROM goose-agent

USER root

# Server management tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    rsync \
    net-tools \
    iputils-ping \
    dnsutils \
    htop \
    tmux \
    vim \
    && rm -rf /var/lib/apt/lists/*

USER goose
WORKDIR /workspace
