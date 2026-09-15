# AGENT.md

Instructions for AI agents modifying this repository.

## Goal

Provide a simple, project-scoped Docker environment for Goose.

The normal workflow must remain:

```bash
cd my-project
goose-sandbox
```

Prefer:

```text
simple
+
isolated
+
reproducible
+
project-scoped
```

---

## Structure

```text
.
├── .dockerignore
├── .github/workflows/ci.yml
├── .gitignore
├── AGENT.md
├── Dockerfile
├── LICENSE
├── README.md
├── goose-sandbox
├── recipes/            # recipe templates (c, csharp, server)
├── sample.env
└── tests/              # bats suite (see tests/README.md)
    ├── helpers.bash    # mocks docker/git/curl, temp HOME/STATE_DIR
    └── *.bats          # Tier 1-4 unit + integration tests
```

---

## 🔐 Non-negotiable security rules

Only mount the selected project as `/workspace`.

Never mount unrelated host paths such as:

```text
/
$HOME
~/.ssh
~/.config
~/Documents
```

Never mount:

```text
/var/run/docker.sock
```

Never add:

```text
--privileged
```

Keep:

```text
--security-opt=no-new-privileges:true
--cap-drop=ALL
--pids-limit
--memory
```

Do not run Goose as root.

Do not bake secrets into the image with Dockerfile `ENV`, `ARG`, `RUN` or `COPY`.

Runtime provider credentials must come from the external env file, normally:

```text
~/.config/goose-sandbox/.env
```

`sample.env` must contain placeholders only.

---

## 🧠 Persistent Goose state

The host project stores state in:

```text
<project>/.goose-sandbox/
```

The launcher mounts that directory separately as:

```text
/goose-state
```

The image defines:

```dockerfile
ENV GOOSE_PATH_ROOT=/goose-state
```

The launcher hides the host state directory from the project tree using a tmpfs at:

```text
/workspace/.goose-sandbox
```

This separation is intentional:

- state stays project-specific and persistent;
- Goose can read/write it through `/goose-state`;
- normal source analysis does not need to traverse internal state under `/workspace`.

Do not move state back into the visible project tree without a clear technical reason.

`.goose-sandbox/` must remain ignored by Git.

---

## 🐳 Docker principles

The container should remain:

- disposable;
- reproducible;
- non-root;
- project-scoped;
- independent from host development tooling.

Pin external container versions instead of using floating `latest` tags.

Do not replace the official pinned uv image copy with `curl | sh`.

Prefer installing project tooling in the Dockerfile rather than requiring it on the host.

Do not introduce Docker Compose, Docker-in-Docker, Kubernetes or background services unless explicitly requested.

---

## 🧪 Recipes (per-project tooling)

The base `Dockerfile` (image `goose-agent`) must stay minimal: only common
agent tools, uv, workspace/state dirs, `USER goose` and `ENTRYPOINT`. It pins
Goose `v1.50.0`. Do **not** re-add language/server toolchains to the base image;
they belong in project recipes.

Project recipes are managed with `goose-sandbox recipe ...`
(`list`, `init`, `add`, `select`, `edit`, `remove`) and stored in
`<project>/.goose-sandbox/recipes/<name>/` (the active one is recorded in
`<project>/.goose-sandbox/recipes/.active`). Each recipe has:

- `Dockerfile` — a full Dockerfile `FROM goose-agent` installing toolchains.
  It must end by switching back to `USER goose` and `WORKDIR /workspace`.
- `skills/` — skills (`<name>/SKILL.md`), mounted, never copied.
- `mcp.txt` — MCP servers, one per line (`name=command` or an `http(s)` URL).

Legacy locations (`GOOSE_SANDBOX_RECIPE`, `.goose-sandbox/recipe.dockerfile`,
`.goose-sandbox/recipe/Dockerfile`) are still detected.

Recipe templates are in `recipes/`: `c`, `csharp`, `server` (`.dockerfile`
files) plus `example/` (a directory with `Dockerfile`, `mcp.txt`, `skills/`).
Keep them small, self-contained and each built `FROM goose-agent`.

The launcher `goose-sandbox`:

- detects the active recipe (`GOOSE_SANDBOX_RECIPE`, `recipe.dockerfile`,
  `recipe/Dockerfile`, then `.goose-sandbox/recipes/<active>/Dockerfile`);
- builds `goose-agent:<project>-<content-hash>` from the base + recipe, where the
  hash is a cryptographic digest of the complete recipe build context (the
  `Dockerfile` plus every file in the recipe directory, e.g. `COPY`/`ADD`
  sources) — so projects with the same name don't collide and editing the
  recipe (or any file it builds from) triggers an automatic rebuild
  (`GOOSE_SANDBOX_REBUILD=1` forces a rebuild; `GOOSE_SANDBOX_IMAGE` skips it).
  The hash covers every file in the recipe directory and does not parse a
  `.dockerignore`, so keep each recipe in its own directory (the managed layout
  already does) so unrelated files don't trigger spurious rebuilds;
- **mounts** global skills (`~/.config/goose/skills`) over the goose global
  skills path (`/home/goose/.agents/skills`) and mounts the recipe `skills/`
  (or `.goose-sandbox/skills/` without a recipe) over the goose
  backward-compatible project skills path (`/workspace/.goose/skills`) whenever
  it exists — it never copies them. Project skills installed by `skills add`
  (or created by goose during a session) live in `<project>/.agents/skills`,
  inside `/workspace`, so they are always visible and nothing is masked;
- turns `recipe/mcp.txt` into `--with-extension` /
  `--with-streamable-http-extension` flags for `goose session`.

Recipes respect the same non-negotiable security rules: non-root at runtime
(end with `USER goose`), no secrets baked in, no Docker socket, no
`--privileged`, no mounting of unrelated host paths.

## 🛠 Self-management and skills

The launcher can install and update itself (`goose-sandbox install`,
`goose-sandbox update`). `install` copies the launcher to `~/.local/bin`
(or `--dir` / `GOOSE_SANDBOX_BIN_DIR`), adds it to the shell `PATH`, and keeps
a git clone of this repository in `GOOSE_SANDBOX_HOME` (default
`~/.local/share/goose-sandbox`). `update` refreshes that managed copy,
reinstalls the launcher and rebuilds the base image.

Skills are managed with the vercel-labs/skills CLI (`npx skills ... --agent
goose`): `goose-sandbox skills add|list|remove [--global]`. Local (default)
installs go into the project at `<project>/.agents/skills` (inside
`/workspace`); global installs go to `~/.config/goose/skills` (mounted at
`/home/goose/.agents/skills`). The launcher must keep `.goose-sandbox/`
git-ignored; `.agents/skills` created by `skills add` in the project may be
committed.

---

## 🌐 Network

Networking is enabled by default because remote LLM providers need it.

`GOOSE_SANDBOX_NETWORK=none` must continue to disable Docker networking.

Do not describe the default configuration as network-isolated.

---

## 📖 Documentation

Keep README instructions:

- concise;
- copy/paste friendly;
- command-first;
- honest about security boundaries.

Do not claim this is equivalent to a hardened VM or a hostile-code sandbox.

If behavior changes, update the README in the same change.

---

## ✅ Validation

After changing `goose-sandbox`:

```bash
bash -n goose-sandbox
shellcheck goose-sandbox
bats tests/                # run the full suite
```

After changing the Dockerfile:

```bash
docker build -t goose-agent .
```

Testing uses [bats](https://bats-core.readthedocs.io/) for unit + mocked
integration tests. `bats` and `shellcheck` are **dev-only** dependencies —
never runtime requirements. New logic that is pure (path/string/parsing) gets
a Tier-1/2 test in `tests/`; logic that shells out to `docker`/`git`/`curl` is
covered via mocked stubs. See `tests/README.md`. Keep the suite green before
merging.

Check the setup:

```bash
goose-sandbox doctor
```

Verify that:

- `/workspace` contains only the selected project mount;
- `.goose-sandbox` persists on the host;
- `/workspace/.goose-sandbox` does not expose persistent state;
- `/goose-state` contains the persistent Goose state;
- unrelated host directories are unavailable;
- the Docker socket is absent;
- Goose runs as a non-root user.

Keep changes small and easy to review.
