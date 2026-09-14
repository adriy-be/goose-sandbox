#!/usr/bin/env bats
# Tier-1 tests: pure functions (no mocks required).
load helpers

@test "project_tag: lowercases and sanitizes the workspace slug" {
    mkdir -p "$TEST_ROOT/ws/My_Project"
    echo "FROM goose-agent" > "$TEST_ROOT/recipe"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/ws/My_Project" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/recipe" resync
    run project_tag
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^goose-agent:my_project--[0-9]+$ ]]
}

@test "project_tag: maps invalid characters to dashes" {
    mkdir -p "$TEST_ROOT/ws/My Proj"
    echo "FROM goose-agent" > "$TEST_ROOT/recipe"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/ws/My Proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/recipe" resync
    run project_tag
    [ "$status" -eq 0 ]
    [[ "$output" == "goose-agent:my-proj-"* ]]
    [[ "$output" != *" "* ]]
    [[ "$output" != *"M"* ]]
}

@test "project_tag: content hash changes with the recipe file" {
    mkdir -p "$TEST_ROOT/ws/proj"
    echo "A" > "$TEST_ROOT/recipe"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/ws/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/recipe" resync
    run project_tag
    local first="$output"
    echo "B" > "$TEST_ROOT/recipe"
    resync
    run project_tag
    [ "$output" != "$first" ]
}

@test "validate_recipe_name: accepts valid names" {
    run validate_recipe_name "c"
    [ "$status" -eq 0 ]
    run validate_recipe_name "my.recipe_1-x"
    [ "$status" -eq 0 ]
}

@test "validate_recipe_name: rejects empty and invalid names" {
    run validate_recipe_name ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid recipe name"* ]]
    run validate_recipe_name "a/b"
    [ "$status" -eq 1 ]
    run validate_recipe_name "a b"
    [ "$status" -eq 1 ]
    run validate_recipe_name "a!"
    [ "$status" -eq 1 ]
}

@test "recipe_template_names: lists directory and .dockerfile templates" {
    run recipe_template_names
    [ "$status" -eq 0 ]
    [[ "$output" == *example* ]]
    [[ "$output" == *c* ]]
    [[ "$output" == *csharp* ]]
    [[ "$output" == *server* ]]
}

@test "recipe_show_paths: prints the recipe file layout" {
    run recipe_show_paths "myrec"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dockerfile: $STATE_DIR/recipes/myrec/Dockerfile"* ]]
    [[ "$output" == *"mcp.txt:    $STATE_DIR/recipes/myrec/mcp.txt"* ]]
}

@test "active_recipe_name: fails when no active recipe" {
    run active_recipe_name
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active recipe selected"* ]]
}

@test "active_recipe_name: returns the active recipe name" {
    mkdir -p "$STATE_DIR/recipes/foo"
    echo "FROM goose-agent" > "$STATE_DIR/recipes/foo/Dockerfile"
    echo "foo" > "$STATE_DIR/recipes/.active"
    run active_recipe_name
    [ "$status" -eq 0 ]
    [ "$output" == "foo" ]
}
