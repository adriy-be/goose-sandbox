# Example project recipe demonstrating a Dockerfile plus skills/ and mcp.txt.
#
# To use in a project, copy this whole directory to
#   <project>/.goose-sandbox/recipe/
# and run `goose-sandbox` from the project. The launcher builds the image
# from this Dockerfile, mounts skills/ and wires up mcp.txt.

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
