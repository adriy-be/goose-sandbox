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

> **Harness gotcha:** the launcher computes its globals (`WORKSPACE`,
> `STATE_DIR`, `RECIPE`, …) once, at source time, from the environment. To test
> a function with different settings, set the `GOOSE_SANDBOX_*` variables and
> re-source with `resync` from `helpers.bash`.
>
> Another gotcha: `run` executes in a subshell, so **globals set inside the
> function do not persist** — assert on `$output`/`$status`, or call the
> function directly when the test checks a modified global.

## Coverage map (Tier 1-4)

| Tier | What | Files |
| --- | --- | --- |
| 1 | Pure functions, no mocks: `project_tag`, `validate_recipe_name`, `recipe_template_names`, `recipe_show_paths`, `active_recipe_name` | `tags.bats` |
| 2 | Env-dependent, no external commands: `ensure_path`, `check_workspace`, `ensure_state_dir` | `paths.bats` |
| 3 | Shell out to `docker`/`git`/`install` (mocked): `cmd_install`, `cmd_update`, `ensure_managed_repo`, `doctor`, `resolve_recipe`, recipe subcommands, `skills_run` | `install.bats`, `doctor.bats`, `recipes.bats`, `skills.bats` |
| 4 | CLI dispatch / exit codes / usage (launcher run as a subprocess) | `cli.bats`, plus dispatch cases in `recipes.bats`/`skills.bats` |

## Adding a test

1. New pure logic → add a Tier-1/2 `@test`; assert on `$status` and `$output`.
2. Logic that shells out → stub the external command with
   `mock_cmd <name> '<script-body>'` and, if you need to inspect the calls,
   have the stub append to a log file (mocked stdout is often consumed by a
   pipeline inside the function under test).
3. Re-source with different settings via `resync` after setting the
   `GOOSE_SANDBOX_*` env vars.
4. Run the suite; keep it green.
