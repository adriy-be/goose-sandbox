#!/usr/bin/env bash
# goose-sandbox lib/doctor.sh
# Responsibility: environment health check and validation.
#
# Exported functions:
#   doctor

doctor() {
    local failed=0

    printf 'Installation:\n'

    if [[ "$SECRETS_BACKEND" == "infisical" ]]; then
        printf '\nSecrets backend: infisical\n'
        if command -v infisical >/dev/null 2>&1; then
            ok "infisical CLI installed"
        else
            fail "infisical CLI not found"
            failed=1
        fi
    else
        printf '\nSecrets backend: env\n'
    fi
    if [[ "$DEV_MODE" == "1" ]]; then
        ok "Development checkout: $SCRIPT_SRC"
    else
        if [[ -d "$SANDBOX_HOME" ]]; then
            ok "Managed home exists: $SANDBOX_HOME"
        else
            fail "Managed home missing: $SANDBOX_HOME"
            failed=1
        fi

        if [[ -f "$SANDBOX_HOME/$SCRIPT_NAME" ]]; then
            ok "Dispatcher exists: $SANDBOX_HOME/$SCRIPT_NAME"
        else
            fail "Dispatcher missing: $SANDBOX_HOME/$SCRIPT_NAME"
            failed=1
        fi

        local lib_ok=1
        for f in config.sh install.sh update.sh recipe.sh skills.sh doctor.sh; do
            if [[ ! -f "$SANDBOX_HOME/lib/$f" ]]; then
                fail "lib/$f missing in managed installation"
                lib_ok=0
                failed=1
            fi
        done
        if [[ $lib_ok -eq 1 ]]; then
            ok "Required lib/ modules present"
        fi
    fi

    if [[ -f "$VERSION_FILE" ]]; then
        ok "Version file readable: $(installed_version)"
    else
        warn "Version file not found at $VERSION_FILE"
    fi

    printf '\nEnvironment:\n'

    if command -v docker >/dev/null 2>&1; then
        ok "Docker installed"
    else
        fail "Docker command not found"
        failed=1
    fi

    if (( failed == 0 )); then
        if docker info >/dev/null 2>&1; then
            ok "Docker daemon reachable"
        else
            fail "Docker daemon is not reachable"
            failed=1
        fi
    fi

    if [[ -f "$ENV_FILE" ]]; then
        ok "Environment file found: $ENV_FILE"
        env_permissions
    else
        fail "Environment file not found: $ENV_FILE"
        failed=1
    fi

    if check_workspace; then
        ok "Workspace writable: $WORKSPACE"
        if ensure_state_dir && [[ -w "$STATE_DIR" ]]; then
            ok "Goose state writable: $STATE_DIR"
        else
            fail "Goose state is not writable: $STATE_DIR"
            failed=1
        fi
    else
        failed=1
    fi

    if [[ -d "$GLOBAL_SKILLS" ]]; then
        if [[ -w "$GLOBAL_SKILLS" ]]; then
            ok "Global skills writable: $GLOBAL_SKILLS"
        else
            fail "Global skills not writable: $GLOBAL_SKILLS"
            failed=1
        fi
    elif [[ -w "$(dirname "$GLOBAL_SKILLS")" ]]; then
        ok "Global skills dir can be created: $GLOBAL_SKILLS"
    else
        fail "Global skills dir not creatable: $GLOBAL_SKILLS"
        failed=1
    fi

    local target="$IMAGE"
    if [[ -n "$RECIPE" ]]; then
        if [[ -z "${GOOSE_SANDBOX_IMAGE:-}" ]]; then
            target="$(project_tag)"
        fi
        ok "Recipe found; image will be: $target"
    fi

    if command -v docker >/dev/null 2>&1 && docker image inspect "$target" >/dev/null 2>&1; then
        ok "Image found: $target"
    else
        warn "Image not found locally: $target"
        warn "Base image:   docker build -t 'goose-agent' .   (in this repo)"
        if [[ -n "$RECIPE" ]]; then
            warn "Recipe image: goose-sandbox will build it on next launch"
        else
            warn "Build it with: docker build -t '$target' ."
        fi
    fi

    printf '\nWorkspace:    %s\n' "$WORKSPACE"
    printf 'Image:        %s\n' "$target"
    printf 'Memory:       %s\n' "$MEMORY"
    printf 'PIDs:         %s\n' "$PIDS"
    printf 'Network:      %s\n' "$NETWORK"
    printf 'Global skills:%s\n' "$GLOBAL_SKILLS"

    if [[ -n "$CPUS" ]]; then
        printf 'CPUs:         %s\n' "$CPUS"
    fi

    if (( failed != 0 )); then
        printf '\nNot ready. Fix the errors above.\n' >&2
        return 1
    fi

    printf '\nReady.\n'
}