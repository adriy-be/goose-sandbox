#!/usr/bin/env bash
# Shared helpers for the goose-sandbox bats suite.
#
# Each test runs in its own temp environment: a fake HOME, workspace, state
# dir, managed-repo dir and a mockbin/ on PATH that stubs docker/git/curl.
# The real launcher is then sourced (its sourcing guard skips the CLI
# dispatch) so tests can call its functions directly.

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goose-sandbox"

# Create a fresh temp environment and source the real launcher.
sandbox_up() {
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME"

    export GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/workspace"
    mkdir -p "$GOOSE_SANDBOX_WORKSPACE"

    export GOOSE_SANDBOX_HOME="$TEST_ROOT/sandbox-home"
    export GOOSE_SANDBOX_BIN_DIR="$TEST_ROOT/bin"
    export GOOSE_SANDBOX_ENV_FILE="$TEST_ROOT/env"
    export GOOSE_SANDBOX_GLOBAL_SKILLS="$TEST_ROOT/home/.config/goose/skills"
    unset GOOSE_SANDBOX_RECIPE GOOSE_SANDBOX_IMAGE GOOSE_SANDBOX_REBUILD

    export MOCK_BIN="$TEST_ROOT/mockbin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"

    # The launcher is a bash script; dispatch is guarded when sourced.
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
}

# Install a stub executable on PATH that records its argv.
# Usage: mock_cmd <name> <script-body>
#   e.g. mock_cmd docker 'echo "docker: $*"'
mock_cmd() {
    local name="$1"
    shift
    printf '#!/usr/bin/env bash\n%s\n' "$1" > "$MOCK_BIN/$name"
    chmod +x "$MOCK_BIN/$name"
}

# Reset all state variables for tests that need to re-source with custom env.
resync() {
    source "$SCRIPT_PATH"
}

# Called by bats before each test: spin up a fresh, isolated sandbox.
setup() {
    sandbox_up
}

teardown() {
    if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}
