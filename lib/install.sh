#!/usr/bin/env bash
# goose-sandbox lib/install.sh
# Responsibility: self-installation of the launcher and managed repo copy.
#
# Exported functions:
#   cmd_install, ensure_managed_repo

ensure_managed_repo() {
    if [[ -d "$SANDBOX_HOME/.git" && -f "$SANDBOX_HOME/goose-sandbox" ]]; then
        ok "Managed repo present: $SANDBOX_HOME"
        return 0
    fi

    mkdir -p "$SANDBOX_HOME"

    if [[ -n "$(ls -A "$SANDBOX_HOME" 2>/dev/null)" && ! -f "$SANDBOX_HOME/goose-sandbox" ]]; then
        fail "Directory exists and does not look like a goose-sandbox copy: $SANDBOX_HOME"
        fail "Move it away or set GOOSE_SANDBOX_HOME to another location"
        return 1
    fi

    if [[ "$DEV_MODE" == "1" ]]; then
        ok "Copying repository into: $SANDBOX_HOME"
        cp -a "$SCRIPT_SRC/." "$SANDBOX_HOME/"
        rm -rf "$SANDBOX_HOME/.goose-sandbox" 2>/dev/null || true
        local ref="dev"
        if [[ -d "$SCRIPT_SRC/.git" ]] && command -v git >/dev/null 2>&1; then
            ref="$(git -C "$SCRIPT_SRC" rev-parse --short HEAD 2>/dev/null || echo dev)"
        fi
        write_version_file "$ref" "dev"
        return 0
    fi

    local ref channel_label
    if [[ "$(effective_channel)" == "main" ]]; then
        ref="$REPO_BRANCH"
        channel_label="main"
    else
        ref="$(resolve_release_tag "$(effective_release_tag)")" || return 1
        channel_label="release"
    fi

    if command -v git >/dev/null 2>&1; then
        ok "Cloning repository ($ref) into: $SANDBOX_HOME"
        git clone --depth 1 --branch "$ref" "$REPO_URL" "$SANDBOX_HOME"
        write_version_file "$ref" "$channel_label"
    else
        fail "git not found; cannot create the managed copy in $SANDBOX_HOME"
        return 1
    fi
}

cmd_install() {
    local dir="${SANDBOX_BIN_DIR:-$HOME/.local/bin}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)
                [[ $# -ge 2 ]] || { fail "--dir needs a value"; return 1; }
                dir="$2"
                shift 2
                ;;
            -h|--help|help)
                usage
                return 0
                ;;
            *)
                fail "Unknown install argument: $1"
                usage
                return 1
                ;;
        esac
    done

    ok "Installing launcher into: $dir"
    mkdir -p "$dir"
    if [[ ! -w "$dir" ]]; then
        fail "Directory not writable: $dir"
        return 1
    fi
    install -m 755 "$SCRIPT_SRC/$SCRIPT_NAME" "$dir/$SCRIPT_NAME"
    ok "Launcher installed: $dir/$SCRIPT_NAME"

    ensure_path "$dir"
    ensure_managed_repo

    if command -v docker >/dev/null 2>&1; then
        ok "Building base image: $BASE_IMAGE"
        docker build -t "$BASE_IMAGE" "$SANDBOX_HOME"
    else
        warn "Docker not found; skip base image build (run 'docker build -t $BASE_IMAGE .' in $SANDBOX_HOME)"
    fi

    printf '\nInstalled.\n'
    printf 'Open a new shell (or: source ~/.bashrc) so PATH picks up %s.\n' "$dir"
    printf 'Check the setup with: %s doctor\n' "$dir/$SCRIPT_NAME"
}