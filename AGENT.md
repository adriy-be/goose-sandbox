# AGENT.md

Instructions for AI agents working in this repository.

## Goal

This repository provides a **Docker-isolated Goose environment**.

The core idea is:

```text
Host project
    │
    ▼
/workspace inside Docker
    │
    ▼
Goose + development tools
```

The agent must stay isolated from the host machine.

---

## Project structure

```text
.
├── Dockerfile
├── README.md
├── goose-sandbox
├── sample.env
└── AGENT.md
```

### Files

* `Dockerfile` — builds the Goose agent environment.
* `goose-sandbox` — launches Goose in Docker.
* `sample.env` — example configuration.
* `README.md` — installation and usage documentation.
* `AGENT.md` — instructions for agents modifying this repository.

---

# 🔐 Security rules

These rules are **non-negotiable**.

## Only mount the selected project

The launcher should expose only the requested workspace:

```text
host current directory
        ↓
/workspace
```

Do not mount unrelated host directories.

Never add mounts such as:

```text
/
$HOME
~/.ssh
~/.config
~/Documents
```

---

## Never mount the Docker socket

Do not add:

```text
/var/run/docker.sock
```

For example, this is forbidden:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

Access to the host Docker daemon would largely defeat the isolation model.

---

## Do not bake secrets into the image

Never put API keys directly into:

```dockerfile
ENV
ARG
RUN
COPY
```

Credentials must come from the external `.env` file at runtime.

Expected location:

```text
~/.config/goose-sandbox/.env
```

---

## Do not commit credentials

`sample.env` must contain placeholders only.

Example:

```env
OPENAI_API_KEY=YOUR_API_KEY
```

Never put a real key in the repository.

---

# 🪿 Goose configuration

The default provider is DeepInfra through its OpenAI-compatible API.

Example:

```env
GOOSE_PROVIDER=openai
OPENAI_HOST=https://api.deepinfra.com
OPENAI_API_KEY=YOUR_API_KEY

GOOSE_MODEL=deepseek-ai/DeepSeek-V3
```

Provider configuration should stay in `.env`, not in the Docker image, unless it is a structural default that does not contain secrets.

---

# 💾 Persistent Goose state

Goose state is intentionally stored inside the mounted project:

```dockerfile
ENV GOOSE_PATH_ROOT=/workspace/.goose-sandbox
```

This allows chat/session state to survive disposable Docker containers.

Expected structure:

```text
project/
├── source files
└── .goose-sandbox/
    ├── config/
    ├── data/
    └── state/
```

Do not change this to `/tmp` unless explicitly requested.

---

## `.goose-sandbox` must not be committed

Projects using the launcher should add:

```gitignore
.goose-sandbox/
```

The directory may contain:

* session history
* Goose state
* local configuration
* generated metadata

---

# 🐳 Docker principles

The container should remain:

* disposable
* reproducible
* non-root when possible
* project-scoped
* independent from host tooling

Prefer installing required development tools in the `Dockerfile` rather than relying on software installed on the host.

---

## Runtime restrictions

Keep security restrictions such as:

```bash
--security-opt=no-new-privileges:true
--cap-drop=ALL
--pids-limit=512
--memory=8g
```

Do not remove them without a clear technical reason.

---

# 📂 Workspace

By default:

```bash
GOOSE_SANDBOX_WORKSPACE="$PWD"
```

must result in:

```text
$PWD → /workspace
```

The current project is the sandbox boundary.

Always set:

```text
working directory = /workspace
```

inside the container.

---

# 🧹 Keep the host clean

Do not require users to install:

* Goose
* Node.js
* Python
* uv
* compilers
* project tooling

on the host when those dependencies can live in the Docker image.

Ideally the host only needs:

```text
Docker
Bash
project files
LLM credentials
```

---

# 🛠️ Making changes

Before modifying the repository:

1. Read `README.md`.
2. Read `Dockerfile`.
3. Read `goose-sandbox`.
4. Read `sample.env`.
5. Preserve the isolation model.

Keep changes small and easy to understand.

---

# ✅ Validation

After changing the `Dockerfile`, build it:

```bash
docker build -t goose-agent .
```

After changing `goose-sandbox`, validate its syntax:

```bash
bash -n goose-sandbox
```

Make sure it is executable:

```bash
chmod +x goose-sandbox
```

Test from another project:

```bash
cd /path/to/test-project
goose-sandbox
```

Verify that:

```text
/workspace
```

contains the selected project.

Also verify that unrelated host paths are not accessible.

---

# 📖 Documentation

If behavior changes, update `README.md`.

Keep documentation:

* concise
* practical
* copy/paste friendly
* easy to scan
* focused on the common workflow first

Prefer:

```text
command
→ result
```

over long theoretical explanations.

---

# 🚫 Avoid unnecessary complexity

Do not introduce:

* Kubernetes
* Docker-in-Docker
* host Docker socket access
* privileged containers
* unnecessary background services
* complex orchestration

unless explicitly requested.

The intended workflow should remain:

```bash
cd my-project
goose-sandbox
```

---

# 🎯 Design principle

When choosing between two implementations, prefer the one that maintains:

```text
simple
+
isolated
+
reproducible
+
project-scoped
```

The repository exists to make running a capable AI agent feel simple without giving that agent unnecessary access to the host.
