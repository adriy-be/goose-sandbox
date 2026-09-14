#!/usr/bin/env bats
# Tier-2 tests: environment-dependent logic (fake HOME/workspace, no mocks).
load helpers

@test "ensure_path: no-op when dir is already on PATH" {
    run ensure_path "$MOCK_BIN"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.bashrc" ]
}

@test "ensure_path: appends export PATH line to .bashrc by default" {
    local dir="$TEST_ROOT/newbin"
    mkdir -p "$dir"
    run ensure_path "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added $dir to PATH"* ]]
    grep -qF "export PATH=\"$dir:\$PATH\"" "$HOME/.bashrc"
}

@test "ensure_path: prefers .zshrc when only it exists" {
    touch "$HOME/.zshrc"
    local dir="$TEST_ROOT/newbin"
    mkdir -p "$dir"
    run ensure_path "$dir"
    [ "$status" -eq 0 ]
    grep -qF "export PATH=\"$dir:\$PATH\"" "$HOME/.zshrc"
    [ ! -e "$HOME/.bashrc" ]
}

@test "ensure_path: uses .profile when neither bash nor zsh rc exists" {
    touch "$HOME/.profile"
    local dir="$TEST_ROOT/newbin"
    mkdir -p "$dir"
    run ensure_path "$dir"
    [ "$status" -eq 0 ]
    grep -qF "export PATH=\"$dir:\$PATH\"" "$HOME/.profile"
}

@test "ensure_path: no duplicate when dir is already referenced in rcfile" {
    local dir="$TEST_ROOT/newbin"
    mkdir -p "$dir"
    echo "export PATH=\"$dir:\$PATH\"" > "$HOME/.bashrc"
    run ensure_path "$dir"
    [ "$status" -eq 0 ]
    [ "$(grep -c "$dir" "$HOME/.bashrc")" -eq 1 ]
}

@test "check_workspace: fails on a missing workspace" {
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/nope" resync
    run check_workspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"Workspace does not exist"* ]]
}

@test "check_workspace: passes on an existing workspace" {
    run check_workspace
    [ "$status" -eq 0 ]
}

@test "ensure_state_dir: creates the state directory" {
    [ ! -d "$STATE_DIR" ]
    run ensure_state_dir
    [ "$status" -eq 0 ]
    [ -d "$STATE_DIR" ]
}
