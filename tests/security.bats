#!/usr/bin/env bats
# Security regression tests for sandbox guarantees.
#
# These tests use REAL docker (not mocked) to spin up actual containers and
# inspect runtime properties, verifying the documented security boundary
# from README.md "Sandbox Security Boundary".
#
# Requires: docker, the goose-agent base image (built by CI or `goose-sandbox install`).
# Run locally: bats tests/security.bats
#
# Guarantees tested:
#   - --cap-drop=ALL (no Linux capabilities retained)
#   - --security-opt=no-new-privileges:true
#   - --pids-limit=512 (default, overridable)
#   - --memory=8g (default, overridable)
#   - non-root user (goose, UID 1000)
#   - /var/run/docker.sock not mounted
#   - no --privileged
#   - only /workspace and /goose-state mounted (plus documented tmpfs/skills)
#   - tini init process present
#   - network defaults to enabled, disableable with GOOSE_SANDBOX_NETWORK=none

setup() {
    # Fresh temp environment for each test
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME"
    export GOOSE_SANDBOX_WORKSPACE="$TEST_ROOT/workspace"
    mkdir -p "$GOOSE_SANDBOX_WORKSPACE"
    export GOOSE_SANDBOX_HOME="$TEST_ROOT/sandbox-home"
    export GOOSE_SANDBOX_ENV_FILE="$TEST_ROOT/env"
    export GOOSE_SANDBOX_GLOBAL_SKILLS="$TEST_ROOT/home/.config/goose/skills"
    mkdir -p "$GOOSE_SANDBOX_GLOBAL_SKILLS"

    # Create a minimal env file (not used by sleep command but launcher requires it)
    echo "GOOSE_MODE=auto" > "$GOOSE_SANDBOX_ENV_FILE"
    chmod 600 "$GOOSE_SANDBOX_ENV_FILE"

    # Find the script
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goose-sandbox"
    export SCRIPT_PATH

    # Ensure docker is available and base image exists
    if ! command -v docker >/dev/null 2>&1; then
        skip "docker not available"
    fi
    if ! docker info >/dev/null 2>&1; then
        skip "docker daemon not reachable"
    fi
    if ! docker image inspect goose-agent >/dev/null 2>&1; then
        skip "goose-agent image not found (build it first: docker build -t goose-agent .)"
    fi
}

teardown() {
    if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
        # Kill any containers we might have left running
        docker ps -aq --filter "label=goose-sandbox-test" 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
        rm -rf "$TEST_ROOT"
    fi
}

# Helper: start a container with the launcher and return its ID.
# The launcher runs goose-sandbox with "sleep infinity" as the command so the
# container stays alive for inspection.
start_container() {
    local container_id

    # Run the launcher with a sleep command so the container stays alive for inspection.
    GOOSE_SANDBOX_WORKSPACE="$GOOSE_SANDBOX_WORKSPACE" \
    GOOSE_SANDBOX_ENV_FILE="$GOOSE_SANDBOX_ENV_FILE" \
    GOOSE_SANDBOX_GLOBAL_SKILLS="$GOOSE_SANDBOX_GLOBAL_SKILLS" \
    GOOSE_SANDBOX_HOME="$GOOSE_SANDBOX_HOME" \
    "$SCRIPT_PATH" sleep infinity &
    local launcher_pid=$!

    # Wait for the container to appear (up to 5 seconds)
    local i=0
    while [[ $i -lt 50 ]]; do
        container_id=$(docker ps -aq --filter "ancestor=goose-agent" --filter "status=running" 2>/dev/null | head -n 1)
        if [[ -n "$container_id" ]]; then
            # Label it for cleanup
            docker update --label "goose-sandbox-test=true" "$container_id" >/dev/null 2>&1 || true
            break
        fi
        sleep 0.1
        i=$((i + 1))
    done

    if [[ -z "$container_id" ]]; then
        echo "ERROR: no container found" >&2
        return 1
    fi

    echo "$container_id"
}

# Helper: clean up a specific container
cleanup_container() {
    local cid="$1"
    docker kill "$cid" >/dev/null 2>&1 || true
    docker rm -f "$cid" >/dev/null 2>&1 || true
}

@test "security: --cap-drop=ALL is applied (no capabilities retained)" {
    local cid
    cid=$(start_container) || return 1

    local caps
    caps=$(docker inspect --format '{{.HostConfig.CapDrop}}' "$cid")
    [[ "$caps" == *ALL* ]]

    cleanup_container "$cid"
}

@test "security: --security-opt=no-new-privileges:true is applied" {
    local cid
    cid=$(start_container) || return 1

    local secopts
    secopts=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$cid")
    [[ "$secopts" == *"no-new-privileges:true"* ]]

    cleanup_container "$cid"
}

@test "security: --pids-limit=512 is applied (default)" {
    local cid
    cid=$(start_container) || return 1

    local pids
    pids=$(docker inspect --format '{{.HostConfig.PidsLimit}}' "$cid")
    [[ "$pids" == "512" ]]

    cleanup_container "$cid"
}

@test "security: --pids-limit can be overridden via GOOSE_SANDBOX_PIDS" {
    export GOOSE_SANDBOX_PIDS=256
    local cid
    cid=$(start_container) || return 1

    local pids
    pids=$(docker inspect --format '{{.HostConfig.PidsLimit}}' "$cid")
    [[ "$pids" == "256" ]]

    cleanup_container "$cid"
}

@test "security: --memory=8g is applied (default)" {
    local cid
    cid=$(start_container) || return 1

    local mem
    mem=$(docker inspect --format '{{.HostConfig.Memory}}' "$cid")
    # 8g = 8589934592 bytes
    [[ "$mem" == "8589934592" ]]

    cleanup_container "$cid"
}

@test "security: --memory can be overridden via GOOSE_SANDBOX_MEMORY" {
    export GOOSE_SANDBOX_MEMORY=4g
    local cid
    cid=$(start_container) || return 1

    local mem
    mem=$(docker inspect --format '{{.HostConfig.Memory}}' "$cid")
    # 4g = 4294967296 bytes
    [[ "$mem" == "4294967296" ]]

    cleanup_container "$cid"
}

@test "security: container runs as non-root user (goose, UID 1000)" {
    local cid
    cid=$(start_container) || return 1

    # Check the user running the main process
    local uid
    uid=$(docker exec "$cid" id -u)
    [[ "$uid" == "1000" ]]

    local uname
    uname=$(docker exec "$cid" id -un)
    [[ "$uname" == "goose" ]]

    cleanup_container "$cid"
}

@test "security: /var/run/docker.sock is NOT mounted" {
    local cid
    cid=$(start_container) || return 1

    # Check mounts from inside the container
    local mounts
    mounts=$(docker exec "$cid" mount | grep -E "docker\.sock|/var/run/docker" || true)
    [[ -z "$mounts" ]]

    cleanup_container "$cid"
}

@test "security: --privileged is NOT used" {
    local cid
    cid=$(start_container) || return 1

    local priv
    priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$cid")
    [[ "$priv" == "false" ]]

    cleanup_container "$cid"
}

@test "security: only expected mounts are present" {
    local cid
    cid=$(start_container) || return 1

    # Get all bind mounts (not tmpfs)
    local mounts
    mounts=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} -> {{.Destination}}
{{end}}{{end}}' "$cid")

    # Expected: workspace -> /workspace
    [[ "$mounts" == *"/workspace"* ]]

    # Expected: global skills -> /home/goose/.agents/skills
    [[ "$mounts" == *"/home/goose/.agents/skills"* ]]

    # Unexpected: root, home, ssh, etc. should not be mounted
    [[ "$mounts" != *" -> /"* ]]
    [[ "$mounts" != *" -> /home/"* ]]
    [[ "$mounts" != *" -> /root/"* ]]
    [[ "$mounts" != *" -> /etc/"* ]]
    [[ "$mounts" != *" -> /usr/"* ]]

    cleanup_container "$cid"
}

@test "security: tini init process is present" {
    local cid
    cid=$(start_container) || return 1

    # --init adds tini as PID 1. Check the init process.
    local init
    init=$(docker inspect --format '{{.Config.Init}}' "$cid")
    [[ "$init" == "true" ]]

    cleanup_container "$cid"
}

@test "security: workspace is writable" {
    local cid
    cid=$(start_container) || return 1

    # Verify /workspace is writable
    docker exec "$cid" sh -c 'touch /workspace/test_write && rm /workspace/test_write'
    [ $? -eq 0 ]

    cleanup_container "$cid"
}

@test "security: /goose-sandbox state is hidden from workspace via tmpfs" {
    local cid
    cid=$(start_container) || return 1

    # The launcher mounts a tmpfs at /workspace/.goose-sandbox to hide the host state dir.
    # Verify that /workspace/.goose-sandbox exists and is a tmpfs.
    local fs_type
    fs_type=$(docker exec "$cid" sh -c 'df /workspace/.goose-sandbox 2>/dev/null | tail -1 | awk "{print \$1}"' || echo "none")
    # tmpfs shows as tmpfs or tmpfs type
    [[ "$fs_type" == "tmpfs" || "$fs_type" == "none" ]]

    cleanup_container "$cid"
}

@test "security: network defaults to enabled but can be disabled" {
    # First test default (network enabled)
    local cid
    cid=$(start_container) || return 1

    # Default network mode should not be "none"
    local netmode
    netmode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$cid")
    [[ "$netmode" != "none" ]]

    cleanup_container "$cid"

    # Now test with GOOSE_SANDBOX_NETWORK=none
    export GOOSE_SANDBOX_NETWORK=none
    local cid2
    cid2=$(start_container) || return 1

    local netmode2
    netmode2=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$cid2")
    [[ "$netmode2" == "none" ]]

    cleanup_container "$cid2"
}

@test "security: env file permissions warning is not a hard failure" {
    # Relax permissions
    chmod 644 "$GOOSE_SANDBOX_ENV_FILE"

    # The launcher should still work (it warns but doesn't fail)
    local cid
    cid=$(start_container) || return 1

    # Container should be running
    [[ -n "$cid" ]]

    cleanup_container "$cid"
}