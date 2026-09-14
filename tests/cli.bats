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
