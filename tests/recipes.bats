#!/usr/bin/env bats
# Tier-3/4 tests: recipe subcommands + dispatch.
load helpers

@test "recipe_init: creates and selects a recipe" {
    run recipe_init myrec
    [ "$status" -eq 0 ]
    [ -f "$STATE_DIR/recipes/myrec/Dockerfile" ]
    [ -f "$STATE_DIR/recipes/myrec/mcp.txt" ]
    [ "$(cat "$STATE_DIR/recipes/.active")" == "myrec" ]
    [[ "$output" == *"Recipe created and selected"* ]]
}

@test "recipe_init: refuses overwrite without --force" {
    run recipe_init myrec
    run recipe_init myrec
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "recipe_init: --force overwrites an existing recipe" {
    run recipe_init myrec
    run recipe_init myrec --force
    [ "$status" -eq 0 ]
}

@test "recipe_add: copies a .dockerfile template" {
    run recipe_add c --as myc
    [ "$status" -eq 0 ]
    [ -f "$STATE_DIR/recipes/myc/Dockerfile" ]
    [ "$(cat "$STATE_DIR/recipes/.active")" == "myc" ]
}

@test "recipe_add: missing template fails" {
    run recipe_add
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing template"* ]]
}

@test "recipe_add: unknown template fails" {
    run recipe_add nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown template"* ]]
}

@test "recipe_add: --no-select adds without selecting" {
    run recipe_add c --as nc --no-select
    [ "$status" -eq 0 ]
    [ ! -e "$STATE_DIR/recipes/.active" ]
}

@test "recipe_select: selects an existing recipe" {
    run recipe_init foo
    run recipe_select foo
    [ "$status" -eq 0 ]
    [ "$(cat "$STATE_DIR/recipes/.active")" == "foo" ]
}

@test "recipe_select: fails for an unknown recipe" {
    run recipe_select nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown local recipe"* ]]
}

@test "recipe_select: missing name fails" {
    run recipe_select
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing recipe name"* ]]
}

@test "recipe_edit: edits Dockerfile and mcp.txt with EDITOR" {
    run recipe_init foo
    EDITOR=true run recipe_edit foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"Editing recipe foo"* ]]
}

@test "recipe_edit: resolves the active recipe when no name given" {
    run recipe_init foo
    EDITOR=true run recipe_edit
    [ "$status" -eq 0 ]
}

@test "recipe_edit: fails for an unknown recipe" {
    run recipe_edit nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown local recipe"* ]]
}

@test "recipe_remove: removes the recipe and clears active selection" {
    run recipe_init foo
    run recipe_remove foo
    [ "$status" -eq 0 ]
    [ ! -d "$STATE_DIR/recipes/foo" ]
    [ ! -e "$STATE_DIR/recipes/.active" ]
    [[ "$output" == *"Recipe removed"* ]]
}

@test "recipe_remove: missing name fails" {
    run recipe_remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing recipe name"* ]]
}

@test "recipe_remove: unknown recipe fails" {
    run recipe_remove nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown local recipe"* ]]
}

@test "recipe_remove: --image queries docker images" {
    mock_cmd docker 'echo "docker: $*" >> "$MOCK_BIN/docker.log"'
    run recipe_init foo
    run recipe_remove foo --image
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recipe removed"* ]]
    grep -q "docker: images" "$MOCK_BIN/docker.log"
}

@test "cmd_recipe: missing subcommand fails" {
    run cmd_recipe
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing recipe subcommand"* ]]
}

@test "cmd_recipe: unknown subcommand fails" {
    run cmd_recipe bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown recipe subcommand"* ]]
}

@test "cmd_recipe: list prints templates and local recipes" {
    run recipe_init foo
    run cmd_recipe list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Built-in templates"* ]]
    [[ "$output" == *"foo"* ]]
}

@test "cmd_recipe: help prints usage" {
    run cmd_recipe -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
