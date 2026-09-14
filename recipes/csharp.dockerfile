# C# / .NET development toolchain.
#
# Copy this file (and optionally its skills/ + mcp.txt) into a project as
#   .goose-sandbox/recipe/Dockerfile
# or set GOOSE_SANDBOX_RECIPE to point at it. Builds on top of the base
# image `goose-agent` (built from the root Dockerfile).

FROM goose-agent

USER root

# .NET SDK (installed with Microsoft's official dotnet-install script)
ENV DOTNET_ROOT=/opt/dotnet
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh \
        | bash -s -- --channel 8.0 --install-dir "$DOTNET_ROOT" \
    && ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet

USER goose
WORKDIR /workspace
ENV PATH="$DOTNET_ROOT:$PATH"
