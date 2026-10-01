#!/usr/bin/env bash
# goose-sandbox lib/recipe.sh
# Responsibility: recipe CRUD, template management, active recipe tracking.
#
# Exported functions:
#   cmd_recipe, recipe_list, recipe_init, recipe_add, recipe_select,
#   recipe_edit, recipe_remove, recipe_usage

recipe_usage() {
    cat <<'USAGE'
Usage:
  goose-sandbox recipe list
  goose-sandbox recipe init [name] [--force]
  goose-sandbox recipe add <template> [--as <name>] [--no-select] [--force]
  goose-sandbox recipe select <name>
  goose-sandbox recipe edit [name]
  goose-sandbox recipe remove <name> [--image]

Templates: c, csharp, server, example
Recipes live in <project>/.goose-sandbox/recipes/<name>/; the active one is
recorded in <project>/.goose-sandbox/recipes/.active.
USAGE
}

recipe_list() {
    printf 'Built-in templates:\n'
    if [[ -d "$TEMPLATES_DIR/recipes" ]]; then
        local names
        names="$(recipe_template_names)"
        if [[ -n "$names" ]]; then
            printf ' %s\n' "$names"
        else
            printf '  (none found)\n'
        fi
    else
        printf '  (none — run "%s install" first)\n' "$SCRIPT_NAME"
    fi

    printf '\nLocal recipes (%s):\n' "$STATE_DIR/recipes"
    local active=""
    if [[ -f "$STATE_DIR/recipes/.active" ]]; then
        active="$(cat "$STATE_DIR/recipes/.active" 2>/dev/null || true)"
    fi
    if [[ -d "$STATE_DIR/recipes" ]]; then
        local any=0
        while IFS= read -r d; do
            local name
            name="$(basename "$d")"
            if [[ "$name" == "$active" ]]; then
                printf '  %s  (active)\n' "$name"
            else
                printf '  %s\n' "$name"
            fi
            any=1
        done < <(find "$STATE_DIR/recipes" -maxdepth 1 -mindepth 1 -type d ! -name '.*' | sort)
        if [[ "$any" == "0" ]]; then
            printf '  (none)\n'
        fi
    else
        printf '  (none)\n'
    fi
}

recipe_init() {
    local name="" force=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=1; shift ;;
            -h|--help) recipe_usage; return 0 ;;
            *) name="$1"; shift ;;
        esac
    done
    [[ -n "$name" ]] || name="default"
    validate_recipe_name "$name" || return 1

    local dest="$STATE_DIR/recipes/$name"
    if [[ -e "$dest" && "$force" == "0" ]]; then
        fail "Recipe already exists: $name (use --force to overwrite)"
        return 1
    fi

    rm -rf "$dest"
    mkdir -p "$dest/skills"
    cat > "$dest/Dockerfile" <<'EOF'
FROM goose-agent

USER root

# Project toolchain — add your tools here, then switch back to goose.
# RUN apt-get update && apt-get install -y --no-install-recommends ...

USER goose
WORKDIR /workspace
EOF
    touch "$dest/mcp.txt"
    printf '%s\n' "$name" > "$STATE_DIR/recipes/.active"
    ok "Recipe created and selected: $name"
    recipe_show_paths "$name"
}

recipe_add() {
    local template="" name="" select=1 force=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --as)
                [[ $# -ge 2 ]] || { fail "--as needs a value"; return 1; }
                name="$2"
                shift 2
                ;;
            --no-select) select=0; shift ;;
            --force) force=1; shift ;;
            -h|--help) recipe_usage; return 0 ;;
            *) template="$1"; shift ;;
        esac
    done

    [[ -n "$template" ]] || { fail "Missing template"; recipe_usage; return 1; }
    [[ -n "$name" ]] || name="$template"
    validate_recipe_name "$name" || return 1

    local dest="$STATE_DIR/recipes/$name"
    if [[ -e "$dest" && "$force" == "0" ]]; then
        fail "Recipe already exists: $name (use --force to overwrite)"
        return 1
    fi

    local src="$TEMPLATES_DIR/recipes/$template"
    if [[ -f "$src.dockerfile" ]]; then
        rm -rf "$dest"
        mkdir -p "$dest/skills"
        cp "$src.dockerfile" "$dest/Dockerfile"
        touch "$dest/mcp.txt"
    elif [[ -d "$src" && -f "$src/Dockerfile" ]]; then
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -R "$src/." "$dest/"
        mkdir -p "$dest/skills"
        [[ -f "$dest/mcp.txt" ]] || touch "$dest/mcp.txt"
    else
        local avail
        avail="$(recipe_template_names)"
        fail "Unknown template: $template"
        fail "Available: $avail"
        return 1
    fi

    if [[ "$select" == "1" ]]; then
        printf '%s\n' "$name" > "$STATE_DIR/recipes/.active"
        ok "Recipe added and selected: $name"
    else
        ok "Recipe added: $name (not selected)"
    fi
    recipe_show_paths "$name"
}

recipe_select() {
    local name="${1:-}"
    [[ -n "$name" ]] || { fail "Missing recipe name"; recipe_usage; return 1; }
    validate_recipe_name "$name" || return 1
    if [[ ! -f "$STATE_DIR/recipes/$name/Dockerfile" ]]; then
        fail "Unknown local recipe: $name"
        return 1
    fi
    printf '%s\n' "$name" > "$STATE_DIR/recipes/.active"
    ok "Active recipe: $name"
}

recipe_edit() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        name="$(active_recipe_name)" || return 1
    fi
    validate_recipe_name "$name" || return 1

    local dir="$STATE_DIR/recipes/$name"
    if [[ ! -f "$dir/Dockerfile" ]]; then
        fail "Unknown local recipe: $name"
        return 1
    fi
    [[ -f "$dir/mcp.txt" ]] || touch "$dir/mcp.txt"

    local editor="${EDITOR:-vi}"
    ok "Editing recipe $name with $editor"
    "$editor" "$dir/Dockerfile"
    "$editor" "$dir/mcp.txt"
}

recipe_remove() {
    local name="" remove_image=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) remove_image=1; shift ;;
            -h|--help) recipe_usage; return 0 ;;
            *) name="$1"; shift ;;
        esac
    done

    [[ -n "$name" ]] || { fail "Missing recipe name"; recipe_usage; return 1; }
    validate_recipe_name "$name" || return 1

    local dir="$STATE_DIR/recipes/$name"
    if [[ ! -d "$dir" ]]; then
        fail "Unknown local recipe: $name"
        return 1
    fi

    if [[ "$remove_image" == "1" ]] && command -v docker >/dev/null 2>&1; then
        local slug line tags=()
        slug="$(basename "$WORKSPACE" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
        while IFS= read -r line; do
            [[ -n "$line" ]] && tags+=("$line")
        done < <(docker images --format '{{.Repository}}:{{.Tag}}' | \
            awk -F: -v s="$slug-" '$1=="goose-agent" && index($2,s)==1 {print $1":"$2}')
        if [[ "${#tags[@]}" -eq 0 ]]; then
            warn "No project image found: goose-agent:$slug-*"
        else
            ok "Removing image(s): ${tags[*]}"
            docker rmi "${tags[@]}" >/dev/null 2>&1 || warn "Some images could not be removed"
        fi
    fi

    rm -rf "$dir"

    local active=""
    if [[ -f "$STATE_DIR/recipes/.active" ]]; then
        active="$(cat "$STATE_DIR/recipes/.active" 2>/dev/null || true)"
    fi
    if [[ "$active" == "$name" ]]; then
        rm -f "$STATE_DIR/recipes/.active"
        warn "Removed the active recipe; selection cleared"
    fi
    ok "Recipe removed: $name"
}

cmd_recipe() {
    check_workspace || return 1
    ensure_state_dir

    local sub="${1:-}"
    shift || true
    case "$sub" in
        list) recipe_list ;;
        init) recipe_init "$@" ;;
        add) recipe_add "$@" ;;
        select) recipe_select "$@" ;;
        edit) recipe_edit "$@" ;;
        remove) recipe_remove "$@" ;;
        -h|--help|help) recipe_usage ;;
        "")
            fail "Missing recipe subcommand"
            recipe_usage
            return 1
            ;;
        *)
            fail "Unknown recipe subcommand: $sub"
            recipe_usage
            return 1
            ;;
    esac
}