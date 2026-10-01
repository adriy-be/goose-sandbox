#!/usr/bin/env bash
# goose-sandbox lib/config.sh
# Responsibility: global environment defaults, shared helper functions,
# path/state management, recipe resolution and image tagging.
#
# Exported functions:
#   usage, ok, warn, fail, check_workspace, ensure_state_dir, env_permissions,
#   resolve_recipe, sha256_hash, recipe_context_hash, project_tag, ensure_path,
#   write_version_file, installed_version, active_recipe_name, validate_recipe_name,
#   recipe_template_names, recipe_show_paths

IMAGE="${GOOSE_SANDBOX_IMAGE:-goose-agent}"
ENV_FILE="${GOOSE_SANDBOX_ENV_FILE:-$HOME/.config/goose-sandbox/.env}"
WORKSPACE="${GOOSE_SANDBOX_WORKSPACE:-$PWD}"
MEMORY="${GOOSE_SANDBOX_MEMORY:-8g}"
PIDS="${GOOSE_SANDBOX_PIDS:-512}"
CPUS="${GOOSE_SANDBOX_CPUS:-}"
NETWORK="${GOOSE_SANDBOX_NETWORK:-default}"
STATE_DIR="$WORKSPACE/.goose-sandbox"
RECIPE="${GOOSE_SANDBOX_RECIPE:-}"
REBUILD="${GOOSE_SANDBOX_REBUILD:-0}"
RECIPE_DIR=""
BASE_IMAGE="goose-agent"

REPO_URL="${GOOSE_SANDBOX_REPO_URL:-https://github.com/adriy-be/goose-sandbox.git}"
REPO_BRANCH="${GOOSE_SANDBOX_REPO_BRANCH:-main}"
TARBALL_URL="${GOOSE_SANDBOX_TARBALL_URL:-}"
CHANNEL="${GOOSE_SANDBOX_CHANNEL:-release}"
RELEASE_TAG="${GOOSE_SANDBOX_RELEASE:-latest}"
SANDBOX_HOME="${GOOSE_SANDBOX_HOME:-$HOME/.local/share/goose-sandbox}"
SANDBOX_BIN_DIR="${GOOSE_SANDBOX_BIN_DIR:-}"
VERSION_FILE="$SANDBOX_HOME/.version"
GLOBAL_SKILLS="${GOOSE_SANDBOX_GLOBAL_SKILLS:-$HOME/.config/goose/skills}"

SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="goose-sandbox"
# DEV_MODE: true when running from a development checkout outside SANDBOX_HOME.
# The managed installation in SANDBOX_HOME is NOT a development checkout.
if [[ "$SCRIPT_SRC" == "$SANDBOX_HOME" || "$SCRIPT_SRC" == "$SANDBOX_HOME/"* ]]; then
    DEV_MODE=0
    TEMPLATES_DIR="$SANDBOX_HOME"
else
    DEV_MODE=1
    TEMPLATES_DIR="$SCRIPT_SRC"
fi

usage() {
    cat <<'USAGE'
Usage:
  goose-sandbox [goose session arguments...]
  goose-sandbox doctor
  goose-sandbox install [--dir DIR]
  goose-sandbox update [--release TAG | --edge]
  goose-sandbox version
  goose-sandbox recipe <list|init|add|select|edit|remove> [...]
  goose-sandbox skills <add|list|remove> [--global] [...]

Launcher settings (host environment):
  GOOSE_SANDBOX_IMAGE            Docker image (default: goose-agent)
  GOOSE_SANDBOX_ENV_FILE         Provider env file
  GOOSE_SANDBOX_WORKSPACE        Workspace to mount (default: $PWD)
  GOOSE_SANDBOX_MEMORY           Memory limit (default: 8g)
  GOOSE_SANDBOX_PIDS             PID limit (default: 512)
  GOOSE_SANDBOX_CPUS             Optional CPU limit, e.g. 4
  GOOSE_SANDBOX_NETWORK          Docker network; use "none" to disable networking
  GOOSE_SANDBOX_RECIPE           Project recipe Dockerfile
                                (default: .goose-sandbox/recipe/Dockerfile
                                 or .goose-sandbox/recipe.dockerfile,
                                 else .goose-sandbox/recipes/<active>/Dockerfile)
  GOOSE_SANDBOX_REBUILD          1 to force rebuilding the recipe image
  GOOSE_SANDBOX_HOME             Managed repo copy (default: ~/.local/share/goose-sandbox)
  GOOSE_SANDBOX_BIN_DIR          Install dir for the launcher (default: ~/.local/bin)
  GOOSE_SANDBOX_CHANNEL          Update channel: release (default, stable) or main (edge/dev)
  GOOSE_SANDBOX_RELEASE          Release tag to install (default: latest, resolved via GitHub)
  GOOSE_SANDBOX_TARBALL_URL      Override the release tarball URL used when git is unavailable
  GOOSE_SANDBOX_GLOBAL_SKILLS    Global skills dir (default: ~/.config/goose/skills)
USAGE
}

ok()   { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; }

check_workspace() {
    if [[ ! -d "$WORKSPACE" ]]; then
        fail "Workspace does not exist: $WORKSPACE"
        return 1
    fi
    if [[ ! -w "$WORKSPACE" ]]; then
        fail "Workspace is not writable: $WORKSPACE"
        return 1
    fi
    return 0
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

env_permissions() {
    local mode=""
    if command -v stat >/dev/null 2>&1; then
        mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null || true)"
    fi
    if [[ -z "$mode" ]]; then
        warn "Could not inspect env-file permissions"
        return 0
    fi
    if (( 10#$mode % 100 != 0 )); then
        warn "Environment file permissions are $mode; recommended: chmod 600 '$ENV_FILE'"
    else
        ok "Environment file permissions: $mode"
    fi
}

resolve_recipe() {
    if [[ -z "$RECIPE" ]]; then
        if [[ -f "$STATE_DIR/recipe.dockerfile" ]]; then
            RECIPE="$STATE_DIR/recipe.dockerfile"
        elif [[ -f "$STATE_DIR/recipe/Dockerfile" ]]; then
            RECIPE="$STATE_DIR/recipe/Dockerfile"
        elif [[ -d "$STATE_DIR/recipes" ]]; then
            local active=""
            if [[ -f "$STATE_DIR/recipes/.active" ]]; then
                active="$(cat "$STATE_DIR/recipes/.active" 2>/dev/null || true)"
                active="${active%%[[:space:]]*}"
            fi
            if [[ -n "$active" && -f "$STATE_DIR/recipes/$active/Dockerfile" ]]; then
                RECIPE="$STATE_DIR/recipes/$active/Dockerfile"
            else
                while IFS= read -r d; do
                    if [[ -f "$d/Dockerfile" ]]; then
                        RECIPE="$d/Dockerfile"
                        break
                    fi
                done < <(find "$STATE_DIR/recipes" -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null | sort)
            fi
        fi
    fi
    if [[ -z "$RECIPE" ]]; then
        RECIPE_DIR=""
    else
        RECIPE_DIR="$(cd "$(dirname "$RECIPE")" && pwd)"
    fi
}

sha256_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 | awk -F'= ' '{print $2}'
    else
        fail "No cryptographic hash tool (sha256sum/shasum/openssl) available; cannot compute the recipe image tag"
        return 1
    fi
}

recipe_context_hash() {
    local ctx="${RECIPE_DIR:-}"
    if [[ -z "$ctx" || ! -d "$ctx" ]]; then
        sha256_hash < "$RECIPE"
        return 0
    fi
    (
        cd "$ctx" || exit 1
        find . -type f ! -path './.git/*' -print0 2>/dev/null \
            | sort -z \
            | xargs -0 sha256sum
    ) | sha256_hash
}

project_tag() {
    local slug fp
    slug="$(basename "$WORKSPACE" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
    fp="$(recipe_context_hash | cut -c1-16)"
    printf 'goose-agent:%s-%s\n' "$slug" "$fp"
}

ensure_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
    esac
    local rcfile="$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" && ! -f "$HOME/.bashrc" ]]; then
        rcfile="$HOME/.zshrc"
    elif [[ ! -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" && -f "$HOME/.profile" ]]; then
        rcfile="$HOME/.profile"
    fi
    if [[ -f "$rcfile" ]] && grep -qF "$dir" "$rcfile"; then
        return 0
    fi
    printf '%s\n' "export PATH=\"$dir:\$PATH\"" >> "$rcfile"
    ok "Added $dir to PATH in $rcfile"
}

write_version_file() {
    local version="$1" channel="$2"
    mkdir -p "$SANDBOX_HOME"
    printf 'version=%s\nchannel=%s\ndate=%s\n' \
        "$version" "$channel" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$VERSION_FILE"
}

installed_version() {
    [[ -f "$VERSION_FILE" ]] || return 0
    sed -n 's/^version=//p' "$VERSION_FILE"
}

active_recipe_name() {
    if [[ -f "$STATE_DIR/recipes/.active" ]]; then
        local a
        a="$(cat "$STATE_DIR/recipes/.active" 2>/dev/null || true)"
        if [[ -n "$a" && -f "$STATE_DIR/recipes/$a/Dockerfile" ]]; then
            printf '%s\n' "$a"
            return 0
        fi
    fi
    fail "No active recipe selected"
    return 1
}

validate_recipe_name() {
    local name="$1"
    if [[ -z "$name" || ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        fail "Invalid recipe name: '$name' (allowed: letters, digits, . _ -)"
        return 1
    fi
}

recipe_template_names() {
    local t="$TEMPLATES_DIR/recipes"
    local out=""
    if [[ -d "$t" ]]; then
        while IFS= read -r d; do
            out="$out $(basename "$d")"
        done < <(find "$t" -maxdepth 1 -mindepth 1 -type d ! -name '.*' | sort)
        while IFS= read -r f; do
            out="$out $(basename "$f" .dockerfile)"
        done < <(find "$t" -maxdepth 1 -type f -name '*.dockerfile' ! -name '.*' | sort)
    fi
    printf '%s\n' "$out"
}

recipe_show_paths() {
    local name="$1"
    printf '  Dockerfile: %s/Dockerfile\n' "$STATE_DIR/recipes/$name"
    printf '  skills/:    %s/skills/\n' "$STATE_DIR/recipes/$name"
    printf '  mcp.txt:    %s/mcp.txt\n' "$STATE_DIR/recipes/$name"
}