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
        # git ls-remote returns "SHA REF"; extract the ref column ($2), strip refs/tags/,
        # filter out annotated tag dereferences (^{}), keep only version tags.
        tag="$(git ls-remote --tags "$REPO_URL" 2>/dev/null | awk '{print $2}' \
            | sed 's|^refs/tags/||' | grep -E '^v[0-9]+(\.[0-9]+)*$' \
            | sort -Vu | sort -V | tail -n 1)"
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
    local ref channel_label
    local home_src="$SANDBOX_HOME"

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
        else
            # Tarball fallback when git is not available or not a git repo.
            local gh_repo owner repo tarball_url
            gh_repo="${REPO_URL#https://github.com/}"
            gh_repo="${gh_repo%%.git}"
            owner="${gh_repo%%/*}"
            repo="${gh_repo#*/}"
            if [[ "$channel_label" == "main" ]]; then
                tarball_url="https://github.com/$owner/$repo/archive/refs/heads/$REPO_BRANCH.tar.gz"
            else
                tarball_url="https://github.com/$owner/$repo/archive/refs/tags/$ref.tar.gz"
            fi
            tarball_url="${TARBALL_URL:-$tarball_url}"
            ok "Downloading release tarball ($ref): $tarball_url"
            if ! command -v curl >/dev/null 2>&1; then
                fail "curl not found; cannot download tarball without git"
                return 1
            fi
            if ! command -v tar >/dev/null 2>&1; then
                fail "tar not found; cannot extract tarball without git"
                return 1
            fi
            find "$SANDBOX_HOME" -mindepth 1 -maxdepth 1 ! -name '.version' -exec rm -rf {} + 2>/dev/null || true
            local tmp_tar
            tmp_tar="$(mktemp)" || return 1
            if ! curl -fsSL "$tarball_url" -o "$tmp_tar"; then
                rm -f "$tmp_tar"
                fail "tarball download failed: $tarball_url"
                return 1
            fi
            if ! tar -xzf "$tmp_tar" -C "$SANDBOX_HOME" --strip-components=1; then
                rm -f "$tmp_tar"
                fail "tarball extraction failed"
                return 1
            fi
            rm -f "$tmp_tar"
        fi
        write_version_file "$ref" "$channel_label"
    fi

    local bin_dir="$SANDBOX_BIN_DIR"
    if [[ -z "$bin_dir" ]]; then
        bin_dir="$HOME/.local/bin"
    fi

    mkdir -p "$bin_dir"
    write_wrapper "$bin_dir" "$SANDBOX_HOME" || return 1
    ok "Launcher updated: $bin_dir/$SCRIPT_NAME"

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        ok "Rebuilding base image: $BASE_IMAGE"
        docker build -t "$BASE_IMAGE" "$home_src"
    else
        warn "Docker not reachable; skipped base image rebuild (run 'docker build -t $BASE_IMAGE .' in $home_src)"
    fi

    printf '\nUpdate complete.\n'
}