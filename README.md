# 🪿 Goose Sandbox

Run **Goose inside Docker** with access only to the project you choose.

The goal:

```text
Your PC
│
├── other-projects/      ❌
├── ~/.ssh/              ❌
├── ~/.config/           ❌
│
└── current-project/     ✅
        │
        ▼
   Docker container
        │
        └── /workspace
             ├── project files
             └── .goose-sandbox/
                  └── Goose history + state
```

Goose can work on your project without getting access to the rest of your machine.

---

# 🚀 Quick start

## 1. Build the image

From this repository:

```bash
docker build -t goose-agent .
```

---

## 2. Create the config

```bash
mkdir -p ~/.config/goose-sandbox
cp sample.env ~/.config/goose-sandbox/.env
```

Edit it:

```bash
nano ~/.config/goose-sandbox/.env
```

Add your DeepInfra API key:

```env
GOOSE_PROVIDER=openai
OPENAI_HOST=https://api.deepinfra.com
OPENAI_API_KEY=YOUR_API_KEY

GOOSE_MODEL=deepseek-ai/DeepSeek-V3

GOOSE_MODE=approve
```

Protect the file:

```bash
chmod 600 ~/.config/goose-sandbox/.env
```

---

## 3. Install the launcher

```bash
mkdir -p ~/.local/bin

install -m 755 goose-sandbox ~/.local/bin/goose-sandbox
```

Make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this line to `~/.bashrc` or `~/.zshrc` if needed.

---

# 🧑‍💻 Usage

Go inside any project:

```bash
cd ~/projects/my-project
```

Launch Goose:

```bash
goose-sandbox
```

That's it.

The current directory becomes:

```text
/workspace
```

inside Docker.

---

# 💬 Example

```text
> Analyze this project and explain the architecture.
```

```text
> Run the tests and find what is broken.
```

```text
> Implement the feature described in issue.md.
```

```text
> Refactor this module without changing its behavior.
```

---

# 🧠 Chat history

Goose keeps its project-specific state inside:

```text
.goose-sandbox/
```

because the Docker image defines:

```dockerfile
ENV GOOSE_PATH_ROOT=/workspace/.goose-sandbox
```

So even if the Docker container is deleted:

```text
container
   ↓
deleted ❌

.goose-sandbox/
   ↓
kept ✅
```

Each project therefore gets its **own Goose history**.

Example:

```text
projects/
├── project-a/
│   └── .goose-sandbox/
│
├── project-b/
│   └── .goose-sandbox/
│
└── project-c/
    └── .goose-sandbox/
```

---

# ⚠️ Add this to `.gitignore`

You normally do **not** want Goose history committed to Git.

Add:

```gitignore
.goose-sandbox/
```

---

# 🔐 Isolation

Only the current project is mounted into the container.

Goose does **not** automatically see:

```text
~/.ssh
~/.config
~/Documents
other projects
/
```

The launcher also applies additional Docker restrictions:

```text
no-new-privileges
capabilities dropped
PID limit
memory limit
```

---

# 🚨 Do NOT mount Docker socket

Never add:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

That would allow the container to control Docker on the host and would largely defeat the purpose of the sandbox.

---

# 🛡️ Goose execution modes

Configured with:

```env
GOOSE_MODE=...
```

## `approve`

```env
GOOSE_MODE=approve
```

Goose asks before executing tools.

Recommended while testing the setup.

---

## `auto`

```env
GOOSE_MODE=auto
```

Goose can execute tools without asking.

Useful once you trust the sandbox.

---

## `chat`

```env
GOOSE_MODE=chat
```

Chat only.

No tool execution.

---

# 🌐 DeepInfra

This setup uses DeepInfra through its OpenAI-compatible API.

Example:

```env
GOOSE_PROVIDER=openai

OPENAI_HOST=https://api.deepinfra.com
OPENAI_API_KEY=YOUR_API_KEY

GOOSE_MODEL=deepseek-ai/DeepSeek-V3
```

You can change the model without rebuilding the Docker image.

Example:

```env
GOOSE_MODEL=Qwen/Qwen3-Coder-480B-A35B-Instruct-Turbo
```

---

# 📁 Repository

```text
.
├── Dockerfile
├── README.md
├── goose-sandbox
└── sample.env
```

### `Dockerfile`

Builds the isolated Goose development environment.

### `goose-sandbox`

Launcher available globally from:

```bash
~/.local/bin/goose-sandbox
```

It mounts the **current directory** into `/workspace`.

### `sample.env`

Example provider and Goose configuration.

Copy it to:

```text
~/.config/goose-sandbox/.env
```

---

# 🔄 Typical workflow

```bash
cd ~/projects/my-project
```

```bash
goose-sandbox
```

Work:

```text
> Understand this project first.

> Find the bug in the authentication flow.

> Fix it and run the tests.
```

Exit Goose.

Later:

```bash
cd ~/projects/my-project
goose-sandbox
```

Your project-specific Goose state is still available through:

```text
.goose-sandbox/
```

---

# 🏗️ Architecture

```text
                    DeepInfra
                        ▲
                        │ HTTPS
                        │
                ┌───────┴───────┐
                │ Docker        │
                │               │
                │ Goose         │
                │               │
                │ /workspace    │
                └───────▲───────┘
                        │
                        │ bind mount
                        │
                current project
                        │
                        ├── source code
                        ├── git repository
                        │
                        └── .goose-sandbox/
                            └── persistent state
```

---

# 🎯 Philosophy

The host provides only:

```text
Docker
+
project
+
LLM credentials
```

The agent environment lives inside Docker.

The result is:

* ✅ project-scoped
* ✅ disposable
* ✅ reproducible
* ✅ persistent chat history
* ✅ minimal host filesystem access
* ✅ easy to use

Start a project:

```bash
cd my-project
goose-sandbox
```

And work.
