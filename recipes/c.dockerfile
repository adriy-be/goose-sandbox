# C / C++ development toolchain.
#
# Copy this file (and optionally its skills/ + mcp.txt) into a project as
#   .goose-sandbox/recipe/Dockerfile
# or set GOOSE_SANDBOX_RECIPE to point at it. Builds on top of the base
# image `goose-agent` (built from the root Dockerfile).

FROM goose-agent

USER root

# C / C++ toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    make \
    ninja-build \
    gcc \
    g++ \
    gdb \
    gdb-multiarch \
    binutils \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

USER goose
WORKDIR /workspace
