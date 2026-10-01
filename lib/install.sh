#!/usr/bin/env bash
# goose-sandbox lib/install.sh
# Responsibility: self-installation of the launcher and managed repo copy.
#
# Exported functions:
#   cmd_install, ensure_managed_repo, write_wrapper

write_wrapper() {
    local bin_dir="$1"
    local managed_home="$2"
    local wrapper="$bin_dir/$SCRIPT_NAME"
    local tmp
    tmp="$(mktemp "$wrapper.XXXXXX")" || return 1

    # Escape backslashes and dollar signs for embedding in the heredoc.
    local escaped_home="${managed_home//\\/\\\\}"
    escaped_home="${escaped_home//\$/\\\$}"

    cat > "$tmp" <<WRAPPER
#!/usr/bin/env bash
# goose-sandbox launcher — installed wrapper
# Delegates to the managed installation.
set -euo pipefail
MANAGED_HOME="\${GOOSE_SANDBOX_HOME:-$escaped_home}"
if [[ ! -f "\$MANAGED_HOME/$SCRIPT_NAME" ]]; then
    echo "goose-sandbox: managed installation not found at \$MANAGED_HOME" >&2
    echo "Re-run: \$0 install" >&2
    exit 1
fi
if [[ ! -d "\$MANAGED_HOME/lib" ]]; then
    echo "goose-sandbox: managed installation incomplete (missing lib/) at \$MANAGED_HOME" >&2
    echo "Re-run: \$0 install" >&2
    exit 1
fi
exec "\$MANAGED_HOME/$SCRIPT_NAME" "\$@"
WRAPPER

    chmod 755 "$tmp"
    mv -f "$tmp" "$wrapper"
}

ensure_managed_repo() {
    if [[ -d "$SANDBOX_HOME/.git" && -f "$SANDBOX_HOME/goose-sandbox" && -d "$SANDBOX_HOME/lib" ]]; then
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
        # Tarball fallback when git is not available.
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
        tarball_url="${GOOSE_SANDBOX_TARBALL_URL:-$tarball_url}"
        ok "Downloading release tarball ($ref): $tarball_url"
        if ! command -v curl >/dev/null 2>&1; then
            fail "curl not found; cannot download tarball without git"
            return 1
        fi
        if ! command -v tar >/dev/null 2>&1; then
            fail "tar not found; cannot extract tarball without git"
            return 1
        fi
        # Clean the managed directory (keep .version).
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
        write_version_file "$ref" "$channel_label"
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

    ok "Installing managed installation into: $SANDBOX_HOME"
    if ! ensure_managed_repo; then
        return 1
    fi

    ok "Installing launcher wrapper into: $dir"
    mkdir -p "$dir"
    if [[ ! -w "$dir" ]]; then
        fail "Directory not writable: $dir"
        return 1
    fi
    write_wrapper "$dir" "$SANDBOX_HOME" || return 1
    ok "Launcher installed: $dir/$SCRIPT_NAME"

    ensure_path "$dir"

    if command -v docker >/dev/null 2>&1; then
        ok "Building base image: $BASE_IMAGE"
        docker build -t "$BASE_IMAGE" "$SANDBOX_HOME"
    else
        warn "Docker not found; skip base image build (run 'docker build -t $BASE_IMAGE .' in $SANDBOX_HOME)"
    fi

    printf '\n✓ Managed installation ready\n'
    printf '✓ Launcher installed\n'
    if command -v docker >/dev/null 2>&1; then
        printf '✓ Base image ready\n'
    fi
    printf '✓ goose-sandbox '
    "$dir/$SCRIPT_NAME" version | sed 's/^/  /'

    printf '\n'
}