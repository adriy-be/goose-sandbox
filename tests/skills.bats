#!/usr/bin/env bats
# Tier-3/4 tests: skills subcommands + dispatch, with a mocked npx.
load helpers

@test "skills_run: invokes npx skills with --agent goose" {
    mock_cmd npx 'echo "npx: $*"'
    run skills_run add foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"npx: skills add foo --agent goose"* ]]
}

@test "skills_run: maps ls to list" {
    mock_cmd npx 'echo "npx: $*"'
    run skills_run ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"npx: skills list --agent goose"* ]]
}

@test "skills_run: --global creates the global skills dir and adds -g" {
    mock_cmd npx 'echo "npx: $*"'
    run skills_run add foo --global
    [ "$status" -eq 0 ]
    [ -d "$GLOBAL_SKILLS" ]
    [[ "$output" == *"npx: skills add foo --agent goose -g"* ]]
}

@test "cmd_skills: missing subcommand fails" {
    run cmd_skills
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing skills subcommand"* ]]
}

@test "cmd_skills: unknown subcommand fails" {
    run cmd_skills bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown skills subcommand"* ]]
}

@test "cmd_skills: help prints usage" {
    run cmd_skills -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
