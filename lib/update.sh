#!/usr/bin/env bash
# goose-sandbox lib/update.sh
# Responsibility: self-update logic, version tracking, channel management.
#
# Exported functions:
#   cmd_update, cmd_version, effective_channel, effective_release_tag,
#   resolve_release_tag

resolve_release_tag() {
    local pinned="${1:-latest}"
    if [[ "$pinned" != "latest" ]]; then
        printf '%s\n' "$pinned"
        return 0
    fi
    local gh_repo owner repo json tag
    gh_repo="${REPO_URL#https://github.com/}"
    gh_repo="${gh_repo%%.git}"
    owner="${gh_repo%%/*}"
    repo="${gh_repo#*/}"
    if command -v curl >/dev/null 2>&1; then
        json="$(curl -fsSL "https://api.github.com/repos/$owner/$repo/releases/latest" 2>/dev/null || true)"
        tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
        if [[ -n "$tag" ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
    fi
    if command -v git >/dev/null 2>&1; then
        tag="$(git ls-remote --tags "$REPO_URL" 2>/dev/null | awk '{print $1}' \
            | sed 's/^refs\/tags\///' | grep -E '^v[0-9]+(\.[0-9]+)*$' \
            | sort -V | tail -n 1)"
        if [[ -n "$tag" ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
    fi
    fail "Could not resolve the latest release tag for $REPO_URL"
    return 1
}

effective_channel() {
    printf '%s\n' "${GOOSE_SANDBOX_CHANNEL:-$CHANNEL}"
}

effective_release_tag() {
    printf '%s\n' "${GOOSE_SANDBOX_RELEASE:-$RELEASE_TAG}"
}

cmd_version() {
    local version channel date
    if [[ -f "$VERSION_FILE" ]]; then
        version="$(sed -n 's/^version=//p' "$VERSION_FILE")"
        channel="$(sed -n 's/^channel=//p' "$VERSION_FILE")"
        date="$(sed -n 's/^date=//p' "$VERSION_FILE")"
    else
        version="unknown"
        channel="none"
        date=""
    fi
    printf 'Version: %s\n' "$version"
    printf 'Channel: %s\n' "$channel"
    if [[ -n "$date" ]]; then
        printf 'Installed: %s\n' "$date"
    fi
    return 0
}

cmd_update() {
    local home_src="$SANDBOX_HOME"
    local ref channel_label

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --edge)
                CHANNEL="main"
                shift
                ;;
            --release)
                [[ $# -ge 2 ]] || { fail "--release needs a value"; return 1; }
                RELEASE_TAG="$2"
                shift 2
                ;;
            -h|--help|help)
                usage
                return 0
                ;;
            *)
                fail "Unknown update argument: $1"
                usage
                return 1
                ;;
        esac
    done

    if [[ "$DEV_MODE" == "1" ]]; then
        ok "Development checkout; pulling latest in $SCRIPT_SRC"
        (cd "$SCRIPT_SRC" && git pull --ff-only) || {
            fail "git pull failed in $SCRIPT_SRC"
            return 1
        }
        home_src="$SCRIPT_SRC"
        ref="$(git -C "$SCRIPT_SRC" rev-parse --short HEAD 2>/dev/null || echo dev)"
        write_version_file "$ref" "dev"
    else
        if [[ ! -d "$SANDBOX_HOME" ]]; then
            fail "Not installed (managed repo missing: $SANDBOX_HOME)"
            fail "Run: $SCRIPT_NAME install"
            return 1
        fi

        if [[ "$(effective_channel)" == "main" ]]; then
            ref="$REPO_BRANCH"
            channel_label="main"
        else
            ref="$(resolve_release_tag "$(effective_release_tag)")" || return 1
            channel_label="release"
        fi

        ok "Updating managed repo to $ref: $SANDBOX_HOME"
        if [[ -d "$SANDBOX_HOME/.git" ]] && command -v git >/dev/null 2>&1; then
            (cd "$SANDBOX_HOME" && git fetch --depth 1 origin "$ref" && git reset --hard FETCH_HEAD) || {
                fail "git update failed in $SANDBOX_HOME"
                return 1
            }
        elif command -v curl >/dev/null 2>&1; then
            local gh_repo owner repo tarball
            gh_repo="${REPO_URL#https://github.com/}"
            gh_repo="${gh_repo%%.git}"
            owner="${gh_repo%%/*}"
            repo="${gh_repo#*/}"
            ok "Downloading release tarball ($ref)"
            find "$SANDBOX_HOME" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.version' -exec rm -rf {} + 2>/dev/null || true
            tarball="${TARBALL_URL:-https://github.com/$owner/$repo/archive/refs/tags/$ref.tar.gz}"
            curl -fsSL "$tarball" | tar -xz --strip-components=1 -C "$SANDBOX_HOME" || {
                fail "tarball download failed"
                return 1
            }
        else
            fail "Neither git nor curl available to update"
            return 1
        fi
        write_version_file "$ref" "$channel_label"
    fi

    local bin_dir="$SANDBOX_BIN_DIR"
    local do_reinstall=1
    if [[ "$DEV_MODE" == "1" && -z "$bin_dir" ]]; then
        do_reinstall=0
    fi

    if [[ "$do_reinstall" == "1" ]]; then
        if [[ -z "$bin_dir" ]]; then
            if [[ "$SCRIPT_SRC" != "$SANDBOX_HOME" && -w "$SCRIPT_SRC" && -f "$SCRIPT_SRC/$SCRIPT_NAME" ]]; then
                bin_dir="$SCRIPT_SRC"
            else
                bin_dir="$HOME/.local/bin"
            fi
        fi
        mkdir -p "$bin_dir"
        install -m 755 "$home_src/$SCRIPT_NAME" "$bin_dir/$SCRIPT_NAME"
        ok "Launcher updated: $bin_dir/$SCRIPT_NAME"
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        ok "Rebuilding base image: $BASE_IMAGE"
        docker build -t "$BASE_IMAGE" "$home_src"
    else
        warn "Docker not reachable; skipped base image rebuild (run 'docker build -t $BASE_IMAGE .' in $home_src)"
    fi

    printf '\nUpdate complete.\n'
}