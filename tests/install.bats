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

@test "ensure_managed_repo: clones the pinned release tag in non-dev mode" {
    sandbox_up_nondev
    export GOOSE_SANDBOX_RELEASE=v1.0.0
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    run ensure_managed_repo
    [ "$status" -eq 0 ]
    grep -q "git: clone --depth 1 --branch v1.0.0" "$MOCK_BIN/git.log"
    grep -q "$SANDBOX_HOME" "$MOCK_BIN/git.log"
    [ -f "$SANDBOX_HOME/.version" ]
    grep -q "version=v1.0.0" "$SANDBOX_HOME/.version"
    grep -q "channel=release" "$SANDBOX_HOME/.version"
}

@test "ensure_managed_repo: edge channel clones main" {
    sandbox_up_nondev
    export GOOSE_SANDBOX_CHANNEL=main
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    run ensure_managed_repo
    [ "$status" -eq 0 ]
    grep -q "git: clone --depth 1 --branch main" "$MOCK_BIN/git.log"
    grep -q "channel=main" "$SANDBOX_HOME/.version"
}

@test "cmd_update: dev mode pulls, reinstalls and rebuilds" {
    mock_cmd git 'if [[ "$1" == "-C" ]]; then echo abc1234; else echo "git: $*"; fi'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'echo "docker: $*"'
    run cmd_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"git: pull --ff-only"* ]]
    [[ "$output" == *"Rebuilding base image"* ]]
    grep -q "version=abc1234" "$SANDBOX_HOME/.version"
    grep -q "channel=dev" "$SANDBOX_HOME/.version"
}

@test "cmd_update: release channel fetches and resets to the pinned tag" {
    sandbox_up_nondev
    export GOOSE_SANDBOX_RELEASE=v1.2.0
    mkdir -p "$SANDBOX_HOME/.git"
    touch "$SANDBOX_HOME/goose-sandbox"
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'exit 0'
    run cmd_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating managed repo to v1.2.0"* ]]
    grep -q "git: fetch --depth 1 origin v1.2.0" "$MOCK_BIN/git.log"
    grep -q "git: reset --hard FETCH_HEAD" "$MOCK_BIN/git.log"
    grep -q "version=v1.2.0" "$SANDBOX_HOME/.version"
    grep -q "channel=release" "$SANDBOX_HOME/.version"
}

@test "cmd_update: --release flag pins the tag and rolls back" {
    sandbox_up_nondev
    mkdir -p "$SANDBOX_HOME/.git"
    touch "$SANDBOX_HOME/goose-sandbox"
    printf 'version=v9.9.9\nchannel=release\n' > "$SANDBOX_HOME/.version"
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'exit 0'
    run cmd_update --release v1.0.0
    [ "$status" -eq 0 ]
    grep -q "git: fetch --depth 1 origin v1.0.0" "$MOCK_BIN/git.log"
    grep -q "version=v1.0.0" "$SANDBOX_HOME/.version"
}

@test "cmd_update: edge channel (--edge) tracks main" {
    sandbox_up_nondev
    mkdir -p "$SANDBOX_HOME/.git"
    touch "$SANDBOX_HOME/goose-sandbox"
    mock_cmd git 'echo "git: $*" >> "$MOCK_BIN/git.log"'
    mock_cmd install 'dest="${@: -1}"; mkdir -p "$(dirname "$dest")"; touch "$dest"'
    mock_cmd docker 'exit 0'
    run cmd_update --edge
    [ "$status" -eq 0 ]
    grep -q "git: fetch --depth 1 origin main" "$MOCK_BIN/git.log"
    grep -q "channel=main" "$SANDBOX_HOME/.version"
}

@test "cmd_update: unknown argument fails with usage" {
    run cmd_update --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown update argument"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "cmd_version: reports the recorded version and channel" {
    mkdir -p "$SANDBOX_HOME"
    printf 'version=v1.0.0\nchannel=release\ndate=2026-01-01T00:00:00Z\n' > "$SANDBOX_HOME/.version"
    run cmd_version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version: v1.0.0"* ]]
    [[ "$output" == *"Channel: release"* ]]
}

@test "cmd_version: reports unknown when no version file exists" {
    run cmd_version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version: unknown"* ]]
}
