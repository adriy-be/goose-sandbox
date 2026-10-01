#!/usr/bin/env bats
# Integration tests: real installation into a temporary HOME, then execution.
# These tests must fail on the pre-fix implementation where the installed
# CLI cannot find lib/*.sh.

load helpers

setup() {
    env_up
}

teardown() {
    if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

@test "install: wrapper is installed, not the full launcher" {
    # Create a fake dev checkout (copy of the repo).
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # Source from the dev checkout so DEV_MODE=1.
    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # The installed file should be the tiny wrapper, not the full launcher.
    # The wrapper is much smaller (< 500 bytes).
    local wrapper_size
    wrapper_size="$(stat -c '%s' "$SANDBOX_BIN_DIR/goose-sandbox" 2>/dev/null || stat -f '%z' "$SANDBOX_BIN_DIR/goose-sandbox" 2>/dev/null)"
    [ "$wrapper_size" -lt 1000 ]
}

@test "install: installed CLI executes (version)" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # This is the critical regression test: execute the installed CLI.
    run "$SANDBOX_BIN_DIR/goose-sandbox" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version:"* ]]
}

@test "install: installed CLI executes (--help)" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    run "$SANDBOX_BIN_DIR/goose-sandbox" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "install: installed CLI works without lib/ beside it" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # Verify there's no lib/ in the bin directory.
    [ ! -d "$SANDBOX_BIN_DIR/lib" ]

    # But the CLI still works (lib/ is in the managed home).
    run "$SANDBOX_BIN_DIR/goose-sandbox" version
    [ "$status" -eq 0 ]
}

@test "install: update does not break installed launcher" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"
    mkdir -p "$DEV_CHECKOUT/.git"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # Run update from the managed installation (non-dev mode).
    export SCRIPT_SRC="$SANDBOX_HOME"
    DEV_MODE=0
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"; if [[ "$1" == "ls-remote" ]]; then echo "abc123 refs/tags/v1.0.0"; fi'
    mock_cmd curl 'echo ""'  # Fail silently to force git fallback
    run cmd_update
    echo "DEBUG: update status=$status" >&2
    echo "DEBUG: update output=$output" >&2
    [ "$status" -eq 0 ]

    # Launcher still works after update.
    run "$SANDBOX_BIN_DIR/goose-sandbox" version
    [ "$status" -eq 0 ]
}

@test "install: missing managed installation gives useful error" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # Remove managed installation.
    rm -rf "$SANDBOX_HOME"

    run "$SANDBOX_BIN_DIR/goose-sandbox" version
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* || "$output" == *"missing"* || "$output" == *"Re-run"* ]]
}

@test "install: paths with spaces work" {
    local spaced_bin="$TEST_ROOT/.local bin/goose-sandbox"
    local spaced_home="$TEST_ROOT/.local share/goose-sandbox"
    mkdir -p "$spaced_bin"
    mkdir -p "$spaced_home"

    export SANDBOX_HOME="$spaced_home"
    export SANDBOX_BIN_DIR="$spaced_bin"

    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$spaced_bin"
    [ "$status" -eq 0 ]

    run "$spaced_bin/goose-sandbox" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version:"* ]]
}

@test "install: custom GOOSE_SANDBOX_HOME works" {
    local custom_home="$TEST_ROOT/custom/goose-sandbox"
    export GOOSE_SANDBOX_HOME="$custom_home"
    export SANDBOX_HOME="$custom_home"

    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]

    # Managed installation should be in custom home.
    [ -d "$custom_home" ]
    [ -f "$custom_home/goose-sandbox" ]
    [ -d "$custom_home/lib" ]

    run "$SANDBOX_BIN_DIR/goose-sandbox" version
    [ "$status" -eq 0 ]
}

@test "install: output includes success indicators" {
    DEV_CHECKOUT="$TEST_ROOT/dev-checkout"
    mkdir -p "$DEV_CHECKOUT"
    cp -a "$SCRIPT_PATH" "$DEV_CHECKOUT/goose-sandbox"
    cp -a "$(dirname "$SCRIPT_PATH")/lib" "$DEV_CHECKOUT/lib"
    cp -a "$(dirname "$SCRIPT_PATH")/Dockerfile" "$DEV_CHECKOUT/Dockerfile"
    cp -a "$(dirname "$SCRIPT_PATH")/recipes" "$DEV_CHECKOUT/recipes"

    # shellcheck disable=SC1090
    source "$DEV_CHECKOUT/goose-sandbox"

    run cmd_install --dir "$SANDBOX_BIN_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Managed installation ready"* ]]
    [[ "$output" == *"✓ Launcher installed"* ]]
}

@test "resolve_release_tag: git fallback extracts tag name, not SHA" {
    # Source the launcher to get resolve_release_tag function
    source "$SCRIPT_PATH"

    # Mock git ls-remote to return lines in the format "SHA REF".
    mock_cmd git 'echo "abc123456789 refs/tags/v1.0.0
def456789012 refs/tags/v1.0.0^{}
ghi789012345 refs/tags/v2.0.0
jkl012345678 refs/tags/v2.0.0^{}
mno345678901 refs/tags/v1.5.0"'

    run resolve_release_tag latest
    [ "$status" -eq 0 ]
    # Should pick the highest version tag.
    [ "$output" == "v2.0.0" ]
}

@test "resolve_release_tag: pinned tag passes through" {
    source "$SCRIPT_PATH"
    run resolve_release_tag v1.0.0
    [ "$status" -eq 0 ]
    [ "$output" == "v1.0.0" ]
}

@test "ensure_managed_repo: tarball fallback for non-dev mode without git" {
    sandbox_up_nondev
    export GOOSE_SANDBOX_RELEASE=v1.0.0
    # Mock git to fail on clone, forcing tarball fallback.
    mock_cmd git 'if [[ "$1" == "clone" ]]; then echo "fatal: Remote branch not found" >&2; exit 1; fi; exit 0'
    mock_cmd curl 'echo "curl: $*" >> "$MOCK_BIN/curl.log"; echo ""'
    mock_cmd tar 'echo "tar: $*" >> "$MOCK_BIN/tar.log"'

    run ensure_managed_repo
    echo "DEBUG: status=$status" >&2
    echo "DEBUG: output=$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading release tarball"* ]]
    [ -f "$MOCK_BIN/curl.log" ]
    grep -q "curl: " "$MOCK_BIN/curl.log"
    grep -q "refs/tags/v1.0.0.tar.gz" "$MOCK_BIN/curl.log"
}

@test "ensure_managed_repo: edge tarball uses refs/heads/main" {
    sandbox_up_nondev
    export GOOSE_SANDBOX_CHANNEL=main
    mock_cmd git 'exit 1'
    mock_cmd curl 'echo "curl: $*" >> "$MOCK_BIN/curl.log"; echo ""'
    mock_cmd tar 'echo "tar: $*"'

    run ensure_managed_repo
    [ "$status" -eq 0 ]
    [ -f "$MOCK_BIN/curl.log" ]
    grep -q "refs/heads/main.tar.gz" "$MOCK_BIN/curl.log"
}