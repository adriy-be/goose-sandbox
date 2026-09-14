#!/usr/bin/env bats
# Tier-3 tests: doctor + recipe resolution, with mocked docker.
load helpers

@test "doctor: reports ready with a healthy environment" {
    mock_cmd docker 'case "$1" in info|image) exit 0 ;; *) exit 0 ;; esac'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    mkdir -p "$(dirname "$GOOSE_SANDBOX_GLOBAL_SKILLS")"
    run doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Docker installed"* ]]
    [[ "$output" == *"Environment file found"* ]]
    [[ "$output" == *"Ready."* ]]
}

@test "doctor: flags an unreachable docker daemon" {
    mock_cmd docker 'if [ "$1" = "info" ]; then exit 1; fi; exit 0'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    run doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"Docker daemon is not reachable"* ]]
}

@test "doctor: flags a missing environment file" {
    mock_cmd docker 'exit 0'
    run doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"Environment file not found"* ]]
}

@test "doctor: resolves recipe tag when a recipe is configured" {
    mock_cmd docker 'case "$1" in info|image) exit 0 ;; *) exit 0 ;; esac'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    mkdir -p "$(dirname "$GOOSE_SANDBOX_GLOBAL_SKILLS")"
    mkdir -p "$STATE_DIR/recipes/foo"
    echo "FROM goose-agent" > "$STATE_DIR/recipes/foo/Dockerfile"
    echo "foo" > "$STATE_DIR/recipes/.active"
    resolve_recipe
    run doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recipe found; image will be: goose-agent:"* ]]
}

@test "resolve_recipe: honors GOOSE_SANDBOX_RECIPE" {
    local r="$TEST_ROOT/recipe"
    echo "FROM goose-agent" > "$r"
    GOOSE_SANDBOX_RECIPE="$r" resync
    run resolve_recipe
    [ "$status" -eq 0 ]
    [ "$RECIPE" == "$r" ]
}

@test "resolve_recipe: leaves RECIPE empty when nothing configured" {
    run resolve_recipe
    [ "$status" -eq 0 ]
    [ -z "$RECIPE" ]
}

@test "resolve_recipe: picks up a managed active recipe" {
    mkdir -p "$STATE_DIR/recipes/foo"
    echo "FROM goose-agent" > "$STATE_DIR/recipes/foo/Dockerfile"
    echo "foo" > "$STATE_DIR/recipes/.active"
    # Call directly (not via run) so the RECIPE global persists.
    resolve_recipe
    [ "$RECIPE" == "$STATE_DIR/recipes/foo/Dockerfile" ]
}
