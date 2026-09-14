# 🪿 Goose Sandbox

Run **Goose inside Docker** with access limited to the project you choose.

```text
Your PC
│
├── other-projects/      ❌ not mounted
├── ~/.ssh/              ❌ not mounted
├── ~/.config/           ❌ not mounted
│
└── current-project/     ✅ mounted as /workspace
        │
        └── .goose-sandbox/  → mounted separately as /goose-state
```

Normal workflow:

```bash
cd my-project
goose-sandbox
```

---

## 🚀 Quick start

### 1. Build

```bash
docker build -t goose-agent .
```

The image pins:

- Goose `v1.50.0`
- uv `0.12.1`

Rebuilding does not silently move to a newer Goose release.

> The base image installs only common agent tools. Language/server toolchains are
> **not** baked in — each project defines its own *recipe* (see below) on top of the
> base image.

### 2. Configure

```bash
mkdir -p ~/.config/goose-sandbox
cp sample.env ~/.config/goose-sandbox/.env
chmod 600 ~/.config/goose-sandbox/.env
```

Edit the file and add your API key.

### 3. Install the launcher

```bash
./goose-sandbox install
```

This copies the launcher to `~/.local/bin`, adds it to your `PATH` in
`~/.bashrc` / `~/.zshrc` / `~/.profile`, clones this repository into
`~/.local/share/goose-sandbox` (the managed copy), and builds the base image.

Open a new shell (or `source ~/.bashrc`) so `~/.local/bin` is on your `PATH`.

Override the target with `goose-sandbox install --dir DIR` or
`GOOSE_SANDBOX_BIN_DIR`; the managed copy lives in `GOOSE_SANDBOX_HOME`
(default `~/.local/share/goose-sandbox`).

### 4. Check setup

```bash
goose-sandbox doctor
```

Then, from any project:

```bash
cd ~/projects/my-project
goose-sandbox
```

---

## 🛠 Self-management (install / update)

The launcher installs and updates itself — and everything in the repository.

```bash
goose-sandbox install [--dir DIR]   # install launcher + managed repo + base image
goose-sandbox update                # pull the repo, reinstall launcher, rebuild base image
```

`install` places the launcher in `~/.local/bin` (override with `--dir` or
`GOOSE_SANDBOX_BIN_DIR`) and keeps a git clone of this repository in
`GOOSE_SANDBOX_HOME` (default `~/.local/share/goose-sandbox`) — the source for
the `Dockerfile`, recipe templates and `sample.env`.

`update` refreshes that managed copy (`git fetch` + `reset --hard` on `main`,
or a tarball if git is unavailable), reinstalls the launcher, and rebuilds the
base image so pinned versions (e.g. the Goose version in the `Dockerfile`) are
applied. From a development checkout, `update` simply runs `git pull` and
rebuilds.

---

## 🧪 Recipes (per-project tooling)

The base image is intentionally minimal. Each project can define its own
**recipe** that adds toolchains, skills and MCP servers. The launcher detects
the recipe, builds a project-specific image on top of the base, and runs it.

### Recipe structure

A recipe lives in the project's sandbox directory:

```text
<project>/.goose-sandbox/
└── recipe/
    ├── Dockerfile     # toolchain install, FROM goose-agent
    ├── skills/        # SKILL.md skills, mounted (see below)
    └── mcp.txt        # MCP servers, one per line
```

`recipe/Dockerfile` is a normal Dockerfile built on top of the base image:

```dockerfile
FROM goose-agent
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ cmake make ninja-build gdb binutils \
    && rm -rf /var/lib/apt/lists/*
USER goose
WORKDIR /workspace
```

Ready-made templates live in [`recipes/`](recipes/):

```text
recipes/c.dockerfile        # C / C++ toolchain
recipes/csharp.dockerfile   # .NET SDK
recipes/server.dockerfile   # server management tools
```

### Skills (mounted, never copied)

`recipe/skills/` is **bind-mounted** over the goose global skills path
(`~/.agents/skills`) — it is not copied. A skill installed during a session is
written straight back to `recipe/skills/` and persists. Without a recipe,
installed skills persist into `.goose-sandbox/skills/`.

### MCP servers

`recipe/mcp.txt` declares MCP servers, one per line:

```text
# local stdio server
memory=npx -y @modelcontextprotocol/server-memory
# remote server over HTTP
https://example.com/mcp
```

The launcher passes them to `goose session` as `--with-extension` /
`--with-streamable-http-extension`. MCP installed interactively inside the
sandbox persists via the `/goose-state` mount (`config/config.yaml`).

### Building & overriding

The recipe image is tagged `goose-agent:<project>-<content-hash>`. The hash
comes from the recipe `Dockerfile`, so two projects sharing a folder name never
collide, and **editing the recipe automatically rebuilds** on the next launch
(a changed `Dockerfile` produces a new tag).

```bash
goose-sandbox            # builds the recipe image (auto-rebuild if recipe changed)
GOOSE_SANDBOX_REBUILD=1 goose-sandbox    # force a rebuild even if unchanged
GOOSE_SANDBOX_RECIPE=/path/to/recipe.dockerfile goose-sandbox
GOOSE_SANDBOX_IMAGE=custom-image goose-sandbox   # skip building, use this image
```

---

## 🩺 Doctor

```bash
goose-sandbox doctor
```

Checks:

- ✅ Docker command
- ✅ Docker daemon
- ✅ provider `.env`
- ✅ `.env` permissions
- ✅ workspace
- ✅ persistent Goose state
- ⚠️ local image availability

Example:

```text
✓ Docker installed
✓ Docker daemon reachable
✓ Environment file found
✓ Environment file permissions: 600
✓ Workspace writable
✓ Goose state writable
✓ Image found: goose-agent

Ready.
```

---

## 🧠 Persistent chat history

On the host, each project keeps Goose state in:

```text
.goose-sandbox/
```

Inside Docker that directory is mounted as:

```text
/goose-state
```

and Goose uses:

```text
GOOSE_PATH_ROOT=/goose-state
```

The same host directory is hidden from `/workspace` with a small tmpfs mount.

Result:

```text
project source          /workspace        ✅
Goose internal state    /goose-state      ✅ persistent
state via project tree  /workspace/.goose-sandbox  ❌ hidden
```

This prevents normal project analysis from walking through Goose's own history/state while keeping that state project-specific.

Add this to projects that use the launcher:

```gitignore
.goose-sandbox/
```

---

## 🔐 Security model

This is a **project-scoped Docker sandbox**, not a hardened VM.

```text
Host filesystem
  current project        ✅ accessible
  unrelated directories  ❌ not mounted

Docker socket             ❌ not mounted

Linux privileges
  no-new-privileges       ✅
  capabilities dropped    ✅
  PID limit               ✅
  memory limit            ✅
  init process            ✅

Network                    ⚠️ enabled by default
LLM credentials            ⚠️ available inside container
Project files              ✅ read/write by the agent
```

Do not run untrusted hostile code and assume Docker alone makes it harmless.

### Never mount the Docker socket

Do **not** add:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

That would let the container control the host Docker daemon and largely defeat the isolation model.

---

## 🌐 Network isolation

Remote providers such as DeepInfra need network access, so normal Docker networking stays enabled by default.

For a local/offline provider:

```bash
GOOSE_SANDBOX_NETWORK=none goose-sandbox
```

This adds:

```text
--network=none
```

You can also select another existing Docker network:

```bash
GOOSE_SANDBOX_NETWORK=my-network goose-sandbox
```

---

## ⚙️ Runtime limits

Defaults:

```text
Memory: 8g
PIDs:   512
```

Override them from the host shell:

```bash
GOOSE_SANDBOX_MEMORY=4g goose-sandbox
GOOSE_SANDBOX_PIDS=256 goose-sandbox
GOOSE_SANDBOX_CPUS=4 goose-sandbox
```

These are launcher settings, so they are intentionally separate from the provider credential `.env`.

Available variables:

```text
GOOSE_SANDBOX_IMAGE
GOOSE_SANDBOX_ENV_FILE
GOOSE_SANDBOX_WORKSPACE
GOOSE_SANDBOX_MEMORY
GOOSE_SANDBOX_PIDS
GOOSE_SANDBOX_CPUS
GOOSE_SANDBOX_NETWORK
GOOSE_SANDBOX_HOME
GOOSE_SANDBOX_BIN_DIR
GOOSE_SANDBOX_GLOBAL_SKILLS
```

---

## 🛡️ Goose execution modes

Configure in `~/.config/goose-sandbox/.env`:

```env
GOOSE_MODE=approve
```

Common modes:

```text
approve        asks before tool execution
smart_approve  selective approval
auto           automatic tool execution
chat           no tools
```

Start with `approve`.

---

## 🌐 DeepInfra example

```env
GOOSE_PROVIDER=openai
GOOSE_MODEL=deepseek-ai/DeepSeek-V3

OPENAI_HOST=https://api.deepinfra.com
OPENAI_API_KEY=YOUR_DEEPINFRA_API_KEY
OPENAI_BASE_PATH=v1/openai/chat/completions

GOOSE_MODE=approve
GOOSE_TELEMETRY_ENABLED=false
```

Change the model without rebuilding the image.

---

## 📁 Repository

```text
.
├── .dockerignore
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitignore
├── AGENT.md
├── Dockerfile
├── LICENSE
├── README.md
├── goose-sandbox
├── recipes/
│   ├── c.dockerfile
│   ├── csharp.dockerfile
│   └── server.dockerfile
└── sample.env
```

---

## ✅ Validation

Launcher syntax:

```bash
bash -n goose-sandbox
```

ShellCheck:

```bash
shellcheck goose-sandbox
```

Build:

```bash
docker build -t goose-agent .
```

Setup check:

```bash
goose-sandbox doctor
```

GitHub Actions performs syntax validation, ShellCheck and a Docker build on pushes and pull requests.

---

## 🎯 Philosophy

Keep the host boring:

```text
Docker
+
project files
+
LLM credentials
```

Keep the workflow boring too:

```bash
cd my-project
goose-sandbox
```

Simple, isolated, reproducible and project-scoped.
