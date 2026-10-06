#!/usr/bin/env bats
# Tier-3 tests: secrets backend (env and infisical).
load helpers

@test "secrets_backend: defaults to env" {
    run secrets_backend
    [ "$status" -eq 0 ]
    [ "$output" == "env" ]
}

@test "secrets_backend: accepts infisical" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    run secrets_backend
    [ "$status" -eq 0 ]
    [ "$output" == "infisical" ]
}

@test "secrets_backend: rejects invalid backend" {
    GOOSE_SANDBOX_SECRETS_BACKEND=aws resync
    run secrets_backend
    [ "$status" -eq 1 ]
}

@test "env backend: works without infisical CLI" {
    mock_cmd infisical 'exit 1'
    GOOSE_SANDBOX_SECRETS_BACKEND=env resync
    run secrets_backend
    [ "$status" -eq 0 ]
}

@test "env backend: requires env file" {
    GOOSE_SANDBOX_SECRETS_BACKEND=env resync
    if [[ -f "$ENV_FILE" ]]; then
        rm "$ENV_FILE"
    fi
    run bash -c "source '$SCRIPT_PATH'; secrets_backend; [[ ! -f '$ENV_FILE' ]] && echo 'env file missing'"
    [[ "$output" == *"env file missing"* ]]
}

@test "infisical backend: detects missing CLI" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    # Remove the mock to simulate missing CLI
    rm -f "$MOCK_BIN/infisical"
    run secrets_init_infisical
    [ "$status" -eq 1 ]
    [[ "$output" == *"infisical CLI not found"* ]]
}

@test "infisical backend: detects unauthenticated state" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    mock_cmd infisical '
        if [[ "$1" == "login" ]]; then
            if [[ "$2" == "status" ]]; then
                echo "not authenticated"
                exit 1
            fi
            # login command - simulate failure
            exit 1
        fi
        exit 0
    '
    run secrets_init_infisical
    [ "$status" -eq 1 ]
}

@test "infisical backend: successful auth flow" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    local login_count=0
    mock_cmd infisical "
        if [[ \"\$1\" == \"login\" ]]; then
            if [[ \"\$2\" == \"status\" ]]; then
                echo \"Authenticated as user@example.com\"
                exit 0
            fi
            exit 0
        fi
        exit 0
    "
    run secrets_init_infisical
    [ "$status" -eq 0 ]
}

@test "infisical backend: exports secrets as names only" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    GOOSE_SANDBOX_SECRET_KEYS="OPENAI_API_KEY,ANTHROPIC_API_KEY" resync

    mock_cmd infisical '
        if [[ "$1" == "login" ]]; then
            if [[ "$2" == "status" ]]; then
                echo "Authenticated as user@example.com"
                exit 0
            fi
        elif [[ "$1" == "export" ]]; then
            echo "export OPENAI_API_KEY=\047sk-test123\047"
            echo "export ANTHROPIC_API_KEY=\047sk-ant456\047"
            exit 0
        fi
        exit 0
    '

    INFISICAL_LOGGED_IN=1
    run secrets_get_infisical
    [ "$status" -eq 0 ]
    [[ "$output" == *"-e OPENAI_API_KEY"* ]]
    [[ "$output" == *"-e ANTHROPIC_API_KEY"* ]]
    [[ ! "$output" == *"sk-test123"* ]]
    [[ ! "$output" == *"sk-ant456"* ]]
}

@test "infisical backend: cleanup on exit" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync

    local logout_called=0
    mock_cmd infisical "
        if [[ \"\$1\" == \"login\" && \"\$2\" == \"status\" ]]; then
            echo \"Authenticated as user@example.com\"
            exit 0
        elif [[ \"\$1\" == \"logout\" ]]; then
            exit 0
        fi
        exit 0
    "

    secrets_init_infisical
    run secrets_cleanup_infisical
    [ "$status" -eq 0 ]
}

@test "infisical backend: self-hosted domain flag" {
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    GOOSE_SANDBOX_INFISICAL_DOMAIN="https://infisical.example.com" resync

    local domain_flag_seen=0
    mock_cmd infisical "
        if [[ \"\$1\" == \"login\" && \"\$2\" == \"status\" ]]; then
            for arg in \"\$@\"; do
                if [[ \"\$arg\" == \"--domain\" ]]; then
                    domain_flag_seen=1
                fi
            done
            echo \"Authenticated as user@example.com\"
            exit 0
        fi
        exit 0
    "

    run secrets_init_infisical
    [ "$status" -eq 0 ]
}

@test "doctor: shows env backend" {
    mock_cmd docker 'exit 0'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    mkdir -p "$(dirname "$GOOSE_SANDBOX_GLOBAL_SKILLS")"
    GOOSE_SANDBOX_SECRETS_BACKEND=env resync
    run doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Secrets backend: env"* ]]
}

@test "doctor: shows infisical backend" {
    mock_cmd docker 'exit 0'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    mkdir -p "$(dirname "$GOOSE_SANDBOX_GLOBAL_SKILLS")"
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    mock_cmd infisical 'exit 0'
    run doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Secrets backend: infisical"* ]]
}

@test "doctor: infisical mode checks CLI" {
    mock_cmd docker 'exit 0'
    touch "$GOOSE_SANDBOX_ENV_FILE"
    mkdir -p "$(dirname "$GOOSE_SANDBOX_GLOBAL_SKILLS")"
    GOOSE_SANDBOX_SECRETS_BACKEND=infisical resync
    run doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"infisical CLI not found"* ]]
}
