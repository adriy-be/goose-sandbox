#!/usr/bin/env bash
# goose-sandbox lib/skills.sh
# Responsibility: skills management via vercel-labs/skills CLI wrapper.
#
# Exported functions:
#   cmd_skills, skills_run, skills_usage

skills_usage() {
    cat <<'USAGE'
Usage:
  goose-sandbox skills add <source> [--global] [skills CLI args...]
  goose-sandbox skills list [--global]
  goose-sandbox skills remove <name> [--global] [skills CLI args...]

Skills are managed with the vercel-labs/skills CLI (npx skills ... --agent goose).
Local (default) skills are installed by the skills CLI into the project
(<project>/.agents/skills, inside /workspace) and are always visible to goose.
Global skills (-g) go to ~/.config/goose/skills/ and are mounted into the
sandbox at the goose global skills path.
USAGE
}

skills_run() {
    local sub="$1"
    shift
    [[ "$sub" == "ls" ]] && sub="list"
    [[ "$sub" == "rm" ]] && sub="remove"

    if ! command -v npx >/dev/null 2>&1; then
        fail "npx (Node.js) not found on the host — required to manage skills"
        return 1
    fi

    local global=0
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --global|-g) global=1; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done

    local npx_args=(skills "$sub")
    npx_args+=("${args[@]}")
    npx_args+=(--agent goose)
    if [[ "$global" == "1" ]]; then
        npx_args+=(-g)
        mkdir -p "$GLOBAL_SKILLS"
    fi

    ok "npx ${npx_args[*]}"
    (cd "$WORKSPACE" && npx "${npx_args[@]}")
}

cmd_skills() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        add|list|ls|remove|rm) skills_run "$sub" "$@" ;;
        -h|--help|help) skills_usage ;;
        "")
            fail "Missing skills subcommand"
            skills_usage
            return 1
            ;;
        *)
            fail "Unknown skills subcommand: $sub"
            skills_usage
            return 1
            ;;
    esac
}