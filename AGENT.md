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
└── sample.env
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
```

After changing the Dockerfile:

```bash
docker build -t goose-agent .
```

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
