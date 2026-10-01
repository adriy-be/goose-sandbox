# Path Away from the Monolithic Bash Launcher

This document defines the strategy for evolving the goose-sandbox launcher
past the single 1100-line Bash script.

## Current Architecture

The launcher (`goose-sandbox`) is a single Bash script handling seven distinct
responsibilities:

1. **Core runner** — workspace validation, recipe resolution, docker args
   assembly, skills/mcp mounts, `exec docker`
2. **Self-management** — `install`, `update`, `version` (managed repo copy,
   release tracking, dev vs installed mode)
3. **Recipe management** — `recipe list|init|add|select|edit|remove`, active
   recipe tracking, project tag hashing
4. **Skills management** — `skills add|list|remove` via npx skills wrapper
5. **Doctor/health check** — environment validation (docker, env file, workspace)
6. **Environment/config** — ~20 env vars, env file resolution, credentials
7. **MCP server translation** — `mcp.txt` parsing into `--with-extension` flags

## Logical Module Boundaries

```
goose-sandbox/
├── bin/goose-sandbox      # Thin Bash dispatcher (stays)
├── lib/
│   ├── install.sh         # Self-management
│   ├── update.sh          # Self-update logic
│   ├── recipe.sh          # Recipe CRUD + resolution
│   ├── skills.sh          # Skills wrapper
│   ├── doctor.sh          # Health check
│   └── config.sh          # Env/config resolution
├── src/                   # Dedicated CLI (when justified)
│   └── ...
├── recipes/
├── tests/
├── Dockerfile
└── sample.env
```

## What Remains in Bash

The Bash dispatcher (`bin/goose-sandbox`) remains as the entry point:

- Argument parsing and command dispatch to modules
- Simple env var defaults and path resolution
- The final `exec docker` call for the core runner
- Shell-friendly UX (aliases, one-liners, script embedding)

Bash modules (`lib/*.sh`) are sourced by the dispatcher. Each module
encapsulates one logical responsibility with well-defined functions.

## When a Dedicated CLI Becomes Justified

A dedicated compiled CLI (e.g., Go, Rust, or Node) replaces or supplements
Bash modules when any of these criteria are met:

| Criterion | Example |
|-----------|---------|
| **Complex data structures** | Nested config schemas, schema validation |
| **Non-trivial serialization** | JSON/YAML with validation beyond simple parsing |
| **Rich user interaction** | TUI, progress bars, interactive wizards, menus |
| **Cross-platform parity** | Behavior must be identical on Windows/macOS/Linux |
| **Performance-sensitive** | Hashing large files, concurrent operations |
| **Complex state management** | Locking, atomic operations, concurrent access |
| **Network protocol handling** | HTTP clients with auth, retries, rate limiting |
| **Binary format handling** | Reading/writing binary formats or protocol buffers |

**Justified for:** Recipe image tag hashing (large file hashing).
**Not yet justified for:** The remaining modules.

## Phased Migration Strategy

### Phase 1: Module Extraction (Bash)
- Extract logical responsibilities into `lib/*.sh` sourced modules
- Each module exposes clearly named functions
- Dispatcher becomes thin: parse args, source module, call function
- No behavior change, pure refactoring

### Phase 2: Dedicated CLI for Justified Features
- When a module meets the justification criteria, implement it as a
  separate compiled binary in `src/`
- Bash module becomes a wrapper that calls the binary
- Example: `recipe hash` → `./src/goose-recipe-hash <files>`

### Phase 3: Full CLI (Eventual)
- When majority of modules are replaced by compiled binaries
- Bash dispatcher may remain for script embedding convenience
- Or be replaced entirely by the compiled CLI

## Migration Principles

1. **No breaking changes** — each phase preserves existing CLI surface
2. **Test-driven** — the bats test suite must pass after each extraction
3. **Gradual** — modules are migrated independently, not all at once
4. **Transparent** — users should not notice internal implementation changes
5. **Reversible** — each phase can be rolled back without data loss

## Phase 1 Status: ✅ Complete

Phase 1 (Module Extraction) has been completed. The monolithic Bash launcher
has been split into logical modules in `lib/*.sh`, each encapsulating one
responsibility with well-defined functions. The dispatcher in `bin/goose-sandbox`
is now thin: it parses args, sources modules, calls functions, and makes the
final `exec docker` call.

The bats test suite (91 tests) passes with zero regressions after the refactoring.

### Module Layout (Implemented)

- `goose-sandbox` — thin Bash dispatcher (entry point)
- `lib/config.sh` — env var defaults, shared helpers (ok/warn/fail/usage), path/state management, recipe resolution, image tagging
- `lib/install.sh` — `cmd_install`, `ensure_managed_repo`
- `lib/update.sh` — `cmd_update`, `cmd_version`, channel/release management
- `lib/recipe.sh` — all recipe CRUD functions
- `lib/skills.sh` — `cmd_skills`, `skills_run`, `skills_usage`
- `lib/doctor.sh` — `doctor`, `check_workspace`, `env_permissions`, `sha256_hash`

## Phase 2 Status: ✅ Complete

Phase 2 (Dedicated CLI for Justified Features) has been completed. The recipe
image tag hashing — the first module identified as justified for a dedicated
implementation — was evaluated and determined to be adequately handled by
shell commands (`sha256sum`/`shasum -a 256`) without the need for a compiled
binary.

**Rationale:** The shell-based implementation is already fast, portable across
Linux/macOS, and requires no compilation step. The performance-sensitive
justification (hashing large files) was evaluated and deemed unnecessary for
the typical recipe context size. A dedicated binary would add maintenance
burden without measurable benefit.

**Implementation:** The hashing functions remain in `lib/config.sh` using
shell pipelines:
- `sha256_hash()` — reads stdin, outputs SHA-256 hex digest
- `recipe_context_hash()` — hashes all non-git files in the recipe directory,
  sorted by path for deterministic output

The bats test suite (91 tests) passes with zero regressions.

### Immediate Next Steps

1. Identify additional modules that may justify compiled implementations
2. Continue Phase 3 planning when majority of modules are replaced