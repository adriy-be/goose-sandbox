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

- Goose `v1.36.0`
- uv `0.12.1`

Rebuilding does not silently move to a newer Goose release.

### 2. Configure

```bash
mkdir -p ~/.config/goose-sandbox
cp sample.env ~/.config/goose-sandbox/.env
chmod 600 ~/.config/goose-sandbox/.env
```

Edit the file and add your API key.

### 3. Install launcher

```bash
mkdir -p ~/.local/bin
install -m 755 goose-sandbox ~/.local/bin/goose-sandbox
```

Make sure `~/.local/bin` is in your `PATH`.

For Bash:

```bash
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

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
