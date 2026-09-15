#!/usr/bin/env bats
# Tier-1 tests: pure functions (no mocks required).
load helpers

# Create a recipe dir (Dockerfile + optional extra files), point the env at it,
# re-source, and resolve the recipe so RECIPE_DIR is populated.
setup_recipe() {
    local ws="$1" dir="$2"
    mkdir -p "$ws" "$dir"
    echo "FROM goose-agent" > "$dir/Dockerfile"
    printf 'setup v1\n' > "$dir/setup.sh"
    GOOSE_SANDBOX_WORKSPACE="$ws" \
    GOOSE_SANDBOX_RECIPE="$dir/Dockerfile" resync
    resolve_recipe
}

@test "project_tag: lowercases and sanitizes the workspace slug" {
    setup_recipe "$TEST_ROOT/ws/My_Project" "$TEST_ROOT/recipe"
    run project_tag
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^goose-agent:my_project--[0-9a-f]{16}$ ]]
}

@test "project_tag: maps invalid characters to dashes" {
    setup_recipe "$TEST_ROOT/ws/My Proj" "$TEST_ROOT/recipe"
    run project_tag
    [ "$status" -eq 0 ]
    [[ "$output" == "goose-agent:my-proj-"* ]]
    [[ "$output" != *" "* ]]
    [[ "$output" != *"M"* ]]
}

@test "project_tag: content hash changes when the Dockerfile changes" {
    mkdir -p "$TEST_ROOT/ws/proj" "$TEST_ROOT/recipe"
    echo "FROM goose-agent" > "$TEST_ROOT/recipe/Dockerfile"
    printf 'setup v1\n' > "$TEST_ROOT/recipe/setup.sh"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/ws/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    local first="$output"
    echo "FROM goose-agent AS base" > "$TEST_ROOT/recipe/Dockerfile"
    run project_tag
    [ "$output" != "$first" ]
}

@test "project_tag: content hash changes when a copied context file changes" {
    mkdir -p "$TEST_ROOT/ws/proj" "$TEST_ROOT/recipe"
    echo "FROM goose-agent" > "$TEST_ROOT/recipe/Dockerfile"
    printf 'setup v1\n' > "$TEST_ROOT/recipe/setup.sh"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/ws/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    local first="$output"
    printf 'setup v2\n' > "$TEST_ROOT/recipe/setup.sh"
    run project_tag
    [ "$output" != "$first" ]
}

@test "project_tag: unchanged context keeps a stable tag" {
    setup_recipe "$TEST_ROOT/ws/proj" "$TEST_ROOT/recipe"
    run project_tag
    local first="$output"
    run project_tag
    [ "$output" == "$first" ]
}

@test "project_tag: same basename with different contexts yields distinct tags" {
    mkdir -p "$TEST_ROOT/wsA/proj/recipe" "$TEST_ROOT/wsB/proj/recipe"
    echo "FROM goose-agent" > "$TEST_ROOT/wsA/proj/recipe/Dockerfile"
    echo "FROM goose-agent" > "$TEST_ROOT/wsB/proj/recipe/Dockerfile"
    printf 'a1\n' > "$TEST_ROOT/wsA/proj/recipe/setup.sh"
    printf 'b1\n' > "$TEST_ROOT/wsB/proj/recipe/setup.sh"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/wsA/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/wsA/proj/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    local tagA="$output"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/wsB/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/wsB/proj/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    [ "$output" != "$tagA" ]
}

@test "project_tag: identical context at different paths shares a compatible tag" {
    mkdir -p "$TEST_ROOT/wsA/proj/recipe" "$TEST_ROOT/wsB/proj/recipe"
    echo "FROM goose-agent" > "$TEST_ROOT/wsA/proj/recipe/Dockerfile"
    echo "FROM goose-agent" > "$TEST_ROOT/wsB/proj/recipe/Dockerfile"
    printf 'setup v1\n' > "$TEST_ROOT/wsA/proj/recipe/setup.sh"
    printf 'setup v1\n' > "$TEST_ROOT/wsB/proj/recipe/setup.sh"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/wsA/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/wsA/proj/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    local tagA="$output"
    GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/wsB/proj" \
    GOOSE_SANDBOX_RECIPE="$TEST_ROOT/wsB/proj/recipe/Dockerfile" resync
    resolve_recipe
    run project_tag
    [ "$output" == "$tagA" ]
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
