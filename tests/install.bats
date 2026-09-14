#!/usr/bin/env bats
# Tier-3 tests: install / update / managed repo, with mocked docker/git/install.
load helpers

@test "cmd_install: --dir installs the launcher and builds the base image" {
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'echo "docker: $*"'
    run cmd_install --dir "$TEST_ROOT/bin"
    [ "$status" -eq 0 ]
    [ -f "$TEST_ROOT/bin/goose-sandbox" ]
    [[ "$output" == *"Installing launcher into: $TEST_ROOT/bin"* ]]
    [[ "$output" == *"docker: build -t goose-agent"* ]]
}

@test "cmd_install: --dir without a value fails" {
    run cmd_install --dir
    [ "$status" -eq 1 ]
    [[ "$output" == *"--dir needs a value"* ]]
}

@test "cmd_install: unknown argument fails with usage" {
    run cmd_install --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown install argument"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "ensure_managed_repo: detects an existing managed repo" {
    mkdir -p "$SANDBOX_HOME/.git"
    touch "$SANDBOX_HOME/goose-sandbox"
    run ensure_managed_repo
    [ "$status" -eq 0 ]
    [[ "$output" == *"Managed repo present"* ]]
}

@test "ensure_managed_repo: refuses a non-empty dir that is not a copy" {
    mkdir -p "$SANDBOX_HOME/other"
    touch "$SANDBOX_HOME/other/foo"
    run ensure_managed_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not look like a goose-sandbox copy"* ]]
}

@test "ensure_managed_repo: copies the repo in DEV_MODE" {
    run ensure_managed_repo
    [ "$status" -eq 0 ]
    [ -f "$SANDBOX_HOME/goose-sandbox" ]
    [[ "$output" == *"Copying repository"* ]]
}

@test "ensure_managed_repo: clones the repo via git in non-dev mode" {
    sandbox_up_nondev
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    run ensure_managed_repo
    [ "$status" -eq 0 ]
    grep -q "git: clone --depth 1 --branch main" "$MOCK_BIN/git.log"
    grep -q "$SANDBOX_HOME" "$MOCK_BIN/git.log"
}

@test "cmd_update: dev mode pulls, reinstalls and rebuilds" {
    mock_cmd git 'echo "git: $*"'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'echo "docker: $*"'
    run cmd_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"git: pull --ff-only"* ]]
    [[ "$output" == *"Rebuilding base image"* ]]
}

@test "cmd_update: non-dev mode fetches and resets the managed repo" {
    sandbox_up_nondev
    mkdir -p "$SANDBOX_HOME/.git"
    touch "$SANDBOX_HOME/goose-sandbox"
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'exit 0'
    run cmd_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating managed repo"* ]]
    grep -q "git: fetch origin main" "$MOCK_BIN/git.log"
    grep -q "git: reset --hard origin/main" "$MOCK_BIN/git.log"
}
