# Test suite (bats)

Unit and mocked-integration tests for the `goose-sandbox` launcher, built with
[bats-core](https://bats-core.readthedocs.io/). Dev-only — `bats` is never a
runtime dependency.

## Install

Linux / macOS / WSL:

```bash
# Debian/Ubuntu
sudo apt-get install -y bats
# macOS (Homebrew)
brew install bats-core
# Anywhere with npm
npm install -g bats
```

Windows: use WSL2 with a Linux distribution (same commands as above).

Optional, for static checks:

```bash
# Debian/Ubuntu
sudo apt-get install -y shellcheck
# macOS
brew install shellcheck
```

## Run

```bash
bash -n goose-sandbox        # syntax
shellcheck goose-sandbox     # static analysis (optional)
bats tests/                  # full suite
bats tests/tags.bats         # single file
bats --filter "cmd_install" tests/   # by test name
```

## How it works

`tests/helpers.bash` gives every test a fresh, isolated sandbox:

- a temp `HOME`, workspace, state dir and managed-repo dir;
- a `mockbin/` directory at the front of `PATH` where tests install stub
  `docker` / `git` / `curl` / `npx` / `install` executables;
- the real `goose-sandbox` is then **sourced** so tests call its functions
  directly. The launcher has a sourcing guard (`BASH_SOURCE[0] != $0` returns
  early) so sourcing loads definitions without running the CLI.

By default the harness runs in `DEV_MODE=1` (the repo layout sits next to the
sourced script). To reach the `DEV_MODE=0` branches — `ensure_managed_repo`'s
git-clone and `cmd_update`'s non-dev fetch/reset paths — call
`sandbox_up_nondev`, which sources a copy of the launcher from a bare temp dir
so `DEV_MODE` is 0.

> **Harness gotcha:** the launcher computes its globals (`WORKSPACE`,
> `STATE_DIR`, `RECIPE`, …) once, at source time, from the environment. To test
> a function with different settings, set the `GOOSE_SANDBOX_*` variables and
> re-source with `resync` from `helpers.bash`.
>
> Another gotcha: `run` executes in a subshell, so **globals set inside the
> function do not persist** — assert on `$output`/`$status`, or call the
> function directly when the test checks a modified global.

## Coverage map (Tier 1-5)

| Tier | What | Files |
| --- | --- | --- |
| 1 | Pure functions, no mocks: `project_tag`, `validate_recipe_name`, `recipe_template_names`, `recipe_show_paths`, `active_recipe_name` | `tags.bats` |
| 2 | Env-dependent, no external commands: `ensure_path`, `check_workspace`, `ensure_state_dir` | `paths.bats` |
| 3 | Shell out to `docker`/`git`/`install` (mocked): `cmd_install`, `cmd_update`, `ensure_managed_repo`, `doctor`, `resolve_recipe`, recipe subcommands, `skills_run` | `install.bats`, `doctor.bats`, `recipes.bats`, `skills.bats` |
| 4 | CLI dispatch / exit codes / usage (launcher run as a subprocess) | `cli.bats`, plus dispatch cases in `recipes.bats`/`skills.bats` |
| 5 | Security regression (real docker, no mocks): validates the documented sandbox security boundary by inspecting actual running containers | `security.bats` |

### Tier-5: Security regression tests (`security.bats`)

These tests use **real docker** (not mocked) to spin up actual containers and
inspect runtime properties, verifying the documented security boundary from
README.md "Sandbox Security Boundary".

Requires: docker, the `goose-agent` base image (built by CI or
`goose-sandbox install`). Skips automatically if docker or the image is missing.

Guarantees tested:
- `--cap-drop=ALL` (no Linux capabilities retained)
- `--security-opt=no-new-privileges:true`
- `--pids-limit=512` (default, overridable)
- `--memory=8g` (default, overridable)
- non-root user (goose, UID 1000)
- `/var/run/docker.sock` not mounted
- no `--privileged`
- only `/workspace` and `/goose-state` mounted (plus documented tmpfs/skills)
- tini init process present
- network defaults to enabled, disableable with `GOOSE_SANDBOX_NETWORK=none`

Run locally:
```bash
bats tests/security.bats
```

## Adding a test

1. New pure logic → add a Tier-1/2 `@test`; assert on `$status` and `$output`.
2. Logic that shells out → stub the external command with
   `mock_cmd <name> '<script-body>'` and, if you need to inspect the calls,
   have the stub append to a log file (mocked stdout is often consumed by a
   pipeline inside the function under test).
3. Re-source with different settings via `resync` after setting the
   `GOOSE_SANDBOX_*` env vars.
4. Run the suite; keep it green.
