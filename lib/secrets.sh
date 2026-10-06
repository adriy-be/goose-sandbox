#!/usr/bin/env bash
# goose-sandbox lib/secrets.sh
# Responsibility: secrets backend selection and Infisical integration.
#
# Exported functions:
#   secrets_backend, secrets_init_infisical,
#   secrets_get_infisical, secrets_cleanup_infisical

INFISICAL_LOGGED_IN=0

secrets_backend() {
    case "$SECRETS_BACKEND" in
        env|infisical) printf '%s\n' "$SECRETS_BACKEND" ;;
        *)
            fail "Invalid secrets backend: $SECRETS_BACKEND (expected env or infisical)"
            return 1
            ;;
    esac
}

secrets_init_infisical() {
    if ! command -v infisical >/dev/null 2>&1; then
        fail "infisical CLI not found; install it or set GOOSE_SANDBOX_SECRETS_BACKEND=env"
        return 1
    fi

    local domain_args=()
    if [[ -n "$INFISICAL_DOMAIN" ]]; then
        domain_args=(--domain "$INFISICAL_DOMAIN")
    fi

    local status
    status="$(infisical login status "${domain_args[@]}" 2>&1 || true)"
    if ! printf '%s' "$status" | grep -q 'Authenticated'; then
        ok "Authenticating to Infisical..."
        if [[ -t 0 ]]; then
            if ! infisical login "${domain_args[@]}" -i; then
                fail "Infisical login failed"
                return 1
            fi
        else
            if ! infisical login "${domain_args[@]}"; then
                fail "Infisical login failed"
                return 1
            fi
        fi
    else
        ok "Already authenticated to Infisical"
    fi
    INFISICAL_LOGGED_IN=1
    return 0
}

secrets_get_infisical() {
    if [[ "$INFISICAL_LOGGED_IN" -ne 1 ]]; then
        secrets_init_infisical || return 1
    fi

    local domain_args=()
    if [[ -n "$INFISICAL_DOMAIN" ]]; then
        domain_args=(--domain "$INFISICAL_DOMAIN")
    fi

    local exported
    if ! exported="$(infisical export --format=dotenv-eval --env "$INFISICAL_ENV" "${domain_args[@]}" 2>/dev/null)"; then
        fail "Failed to export secrets from Infisical"
        return 1
    fi

    # Parse dotenv-eval output safely (export KEY='value' lines)
    while IFS= read -r line; do
        # Match: export KEY='value' or export KEY="value"
        if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)='(.*)'$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            export "$key"="$val"
        elif [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)="(.*)"$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            export "$key"="$val"
        fi
    done <<< "$exported"

    local keys_arr=()
    IFS=',' read -ra keys_arr <<< "$SECRET_KEYS"

    local env_args=()
    for key in "${keys_arr[@]}"; do
        key="${key%%[[:space:]]*}"
        key="${key##[[:space:]]}"
        if [[ -n "$key" ]]; then
            env_args+=(-e "$key")
        fi
    done

    local result=""
    for arg in "${env_args[@]}"; do
        if [[ -n "$result" ]]; then
            result="$result $arg"
        else
            result="$arg"
        fi
    done
    printf '%s\n' "$result"
}

secrets_cleanup_infisical() {
    if [[ "$INFISICAL_LOGGED_IN" -ne 1 ]]; then
        return 0
    fi

    local domain_args=()
    if [[ -n "$INFISICAL_DOMAIN" ]]; then
        domain_args=(--domain "$INFISICAL_DOMAIN")
    fi

    ok "Cleaning up Infisical session..."
    infisical logout --local-only "${domain_args[@]}" >/dev/null 2>&1 || true
    INFISICAL_LOGGED_IN=0
}
