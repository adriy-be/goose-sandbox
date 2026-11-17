#!/usr/bin/env bats
# Tier-4 tests: top-level CLI dispatch (runs the launcher as a subprocess).
load helpers

@test "cli: help prints usage and exits 0" {
    run "$SCRIPT_PATH" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: help subcommand prints usage" {
    run "$SCRIPT_PATH" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: recipe subcommand dispatches to recipe list" {
    run "$SCRIPT_PATH" recipe list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Built-in templates"* ]]
}

@test "cli: install with an unknown argument exits non-zero" {
    run "$SCRIPT_PATH" install --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown install argument"* ]]
}

@test "cli: skills with an unknown subcommand exits non-zero" {
    run "$SCRIPT_PATH" skills bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown skills subcommand"* ]]
}

@test "cli: unknown first argument falls through to the session path and fails without an env file" {
    run "$SCRIPT_PATH" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Environment file not found"* ]]
}

@test "cli: absolute launcher symlink loads modules from the checkout" {
    mkdir -p "$TEST_ROOT/bin"
    ln -s "$SCRIPT_PATH" "$TEST_ROOT/bin/goose-sandbox"
    run "$TEST_ROOT/bin/goose-sandbox" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: relative launcher symlink works from an unrelated directory" {
    mkdir -p "$TEST_ROOT/checkout with spaces" "$TEST_ROOT/bin"
    cp -a "$(dirname "$SCRIPT_PATH")/." "$TEST_ROOT/checkout with spaces/"
    ln -s "../checkout with spaces/goose-sandbox" "$TEST_ROOT/bin/goose-sandbox"
    cd "$GOOSE_SANDBOX_WORKSPACE"
    run "$TEST_ROOT/bin/goose-sandbox" recipe list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Built-in templates"* ]]
    [[ "$output" == *"csharp"* ]]
}

@test "cli: mixed symlink chain works through PATH" {
    mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/links"
    ln -s "$SCRIPT_PATH" "$TEST_ROOT/links/launcher"
    ln -s ../links/launcher "$TEST_ROOT/bin/goose-sandbox"
    export PATH="$TEST_ROOT/bin:$PATH"
    cd "$GOOSE_SANDBOX_WORKSPACE"
    run goose-sandbox --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: symlink through a directory alias resolves relative to physical directory" {
    mkdir -p "$TEST_ROOT/real/bin"
    ln -s "$SCRIPT_PATH" "$TEST_ROOT/real/launcher"
    ln -s ../launcher "$TEST_ROOT/real/bin/goose-sandbox"
    ln -s "$TEST_ROOT/real/bin" "$TEST_ROOT/alias"
    run "$TEST_ROOT/alias/goose-sandbox" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: sourcing a symlink loads definitions without dispatch or changing workspace" {
    ln -s "$SCRIPT_PATH" "$TEST_ROOT/launcher"
    run bash -c 'cd "$GOOSE_SANDBOX_WORKSPACE"; source "$1"; [[ "$WORKSPACE" == "$PWD" ]]; declare -F cmd_install' bash "$TEST_ROOT/launcher"
    [ "$status" -eq 0 ]
    [[ "$output" == "cmd_install" ]]
}
