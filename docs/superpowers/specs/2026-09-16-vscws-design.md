# vscws — per-project VS Code dev containers with shared Claude Code

Date: 2026-09-16
Status: draft for user review

## 1. Goal

- One command creates a workspace for a project. The workspace is a directory under a root the user chooses.
- Opening the workspace in VS Code starts a Docker container built for that project's language, with all build tools inside.
- VS Code installs only the extensions the preset lists. Extensions from the laptop are never pushed into the container.
- The Claude Code panel works in every container using one shared login. No per-container login.
- Projects that have their own Docker containers (compose stacks) run from inside the dev container without Docker-in-Docker.
- Everything is reproducible: one script configures a fresh machine. Works on Ubuntu (any recent release) and macOS.
- Tool and language versions resolve to the latest stable at image build time, not pinned at authoring time.

## 2. Non-goals (v1)

- Docker-in-Docker. Can be added later as an opt-in preset flag.
- Persisting build caches or shell history across image rebuilds. Caches live in the container home and survive stop/start, not rebuild. Rebuilds are rare (tool version bumps).
- Combining several language presets into one workspace. Make a new preset instead.
- Windows.
- Automatic opening of the container from the Mac with zero clicks. Opening the folder over SSH then "Reopen in Container" is one click.

## 3. Topology

Two supported host modes, detected automatically by the tool:

- **Remote (Linux VM)**: VS Code on the Mac → Remote-SSH → VM → Dev Containers extension builds and attaches to the container on the VM.
- **Local (macOS)**: VS Code and Docker Desktop on the same Mac. VS Code opens the folder locally and reopens it in the container.

Both modes use the same `vscws` tool, the same presets, and the same generated `.devcontainer/` files. Only a few generated values differ (see §7).

## 4. Repository layout

```
vscws/
  README.md                       # human-readable bullet-point instructions
  bin/vscws                       # the tool, bash 3.2 compatible (macOS default bash)
  presets/
    _common.json                  # merged into every preset: Claude, docker CLI, gh, base extensions
    cpp/devcontainer.json         # + optional Dockerfile per preset
    cpp/Dockerfile
    go/devcontainer.json
    java/devcontainer.json
  mac/
    settings.json                 # snippet to paste into VS Code user settings on the Mac
    ssh-config.example            # example ~/.ssh/config entry for the VM
  docs/superpowers/specs/         # this spec
```

- The repo is cloned to `~/vscws` on every machine. `vscws setup` symlinks `bin/vscws` into `~/.local/bin`.
- Presets are plain JSON files. Editing a preset is the way to change a language's configuration.

## 5. The `vscws` command

All subcommands, no sudo except `setup`:

| Command | What it does |
|---|---|
| `vscws setup [--root DIR] [--ssh-host NAME]` | One-time machine configuration (§6). Idempotent, re-runnable. |
| `vscws new NAME --preset P [--repo URL]` | Creates `$ROOT/NAME`, optionally clones `URL` into it, writes `.devcontainer/` from preset `P` (§7). Refuses if `NAME` exists. If the cloned repo already has `.devcontainer/`, asks before overwriting. |
| `vscws ls` | Lists workspaces: name, preset, container state (none / stopped / running). |
| `vscws open NAME` | Remote mode: prints the `code --folder-uri vscode-remote://ssh-remote+HOST/path` command to run on the Mac. Local mode: runs `code path`. |
| `vscws build NAME [--no-cache]` | Builds the image and starts the container via `devcontainer up`. Used for testing without VS Code and for `rebuild`. |
| `vscws rebuild NAME` | `build --no-cache` plus removes the existing container. This is how tool versions get bumped to the current latest. |
| `vscws shell NAME` | `devcontainer exec` into a running container (interactive bash). |
| `vscws stop NAME` | Stops the workspace's container. |
| `vscws rm NAME [--force]` | Stops and removes the container. Deletes the directory only after typing the name to confirm. |
| `vscws presets` | Lists available presets with their one-line description. |
| `vscws doctor` | Checks docker, devcontainer CLI, jq, config, Claude login state, prints what is missing. |

- Config file: `~/.config/vscws/config`, shell-sourceable `KEY=VALUE`:
  - `VSCWS_ROOT` — workspace root (e.g. `/data/ws` or `~/ws`).
  - `VSCWS_MODE` — `remote` or `local` (detected: Linux → remote, macOS → local; overridable).
  - `VSCWS_SSH_HOST` — remote mode only: the Host alias from the Mac's `~/.ssh/config`.
  - `VSCWS_CLAUDE_DIR` — host directory shared into containers as Claude config (default `~/.claude`).
- Per-workspace marker: `$ROOT/NAME/.vscws.json` with preset name, creation date, tool version. Used by `ls`, `rebuild`, `rm`.
- Dependencies at runtime: bash 3.2+, `docker`, `jq`, `devcontainer` CLI (for build/rebuild/shell/stop), `git`.

## 6. `vscws setup` (fresh machine configuration)

Detects the platform from `uname`. Idempotent: every step checks before acting and prints what it did or skipped.

### Linux (Ubuntu, any recent release)

1. `apt-get install` curl, git, jq, ca-certificates.
2. Docker: if `docker` is missing, run Docker's official `get.docker.com` script (detects the Ubuntu release itself, no codename hard-coded). Add the user to the `docker` group. Enable the service.
3. `gh`: install from GitHub's apt repository (Ubuntu's own package lags).
4. Node.js: if `node` is missing, install the current LTS from NodeSource. Then `npm install -g @devcontainers/cli`.
5. Claude Code: if `claude` is missing, run the official native installer.
6. Claude shared config layout:
   - Add `export CLAUDE_CONFIG_DIR="$HOME/.claude"` to `~/.profile` and to the top of `~/.bashrc` (before the interactive-shell early return) and `~/.zshrc` if present. Guarded by a marker comment so it is added once.
   - If `~/.claude.json` is a regular file: back it up to `~/.claude/backups/claude.json.<timestamp>`, move it to `~/.claude/.claude.json`, and leave a symlink `~/.claude.json → ~/.claude/.claude.json` so any process started without the variable still finds it.
   - If `~/.claude.json` is already a symlink or absent: nothing.
7. tmux-friendly SSH agent: write `~/.ssh/rc` to refresh a stable symlink `~/.ssh/ssh_auth_sock` on every login, and add `set-environment -g SSH_AUTH_SOCK ~/.ssh/ssh_auth_sock` to `~/.tmux.conf` (marker-guarded). Both only if not already present.
8. Write `~/.config/vscws/config` (asks for root and ssh host if not given as flags; keeps existing values).
9. Symlink `bin/vscws` into `~/.local/bin`, ensure that is on PATH.
10. Print next steps: log out/in for the docker group, `claude` to verify login, `gh auth login`, the Mac settings to paste.

### macOS

1. Requires Homebrew; prints the install command and exits if missing.
2. `brew install` jq, gh, git, node. `brew install --cask docker` if no docker engine is found (Docker Desktop or OrbStack both accepted). Prints "launch Docker Desktop once" if the daemon is not running.
3. `npm install -g @devcontainers/cli`.
4. Claude Code native installer if missing.
5. No change to the host Claude layout. macOS keeps credentials in Keychain, which containers cannot read, so containers share `~/.claude` and the first container asks for one login that all others then reuse.
6. Config file, symlink, next steps as on Linux. Mode defaults to `local`.

## 7. Generated `.devcontainer/`

`vscws new` produces `devcontainer.json` by deep-merging, with `jq`, in this order: `presets/_common.json`, then `presets/P/devcontainer.json`, then a small generated object. Objects merge recursively; the arrays `mounts`, `runArgs`, `features` keys and `customizations.vscode.extensions` are concatenated and de-duplicated. If the preset has a `Dockerfile`, it is copied next to the json, and the merged `image` key is dropped in favour of the preset's `build` key (a devcontainer.json may not have both).

Content of `_common.json`:

- `image`: `mcr.microsoft.com/devcontainers/base:ubuntu` (tracks the latest Ubuntu LTS; non-root user `vscode`). Presets with a Dockerfile use `build` instead and `FROM` the same image.
- `workspaceMount` / `workspaceFolder`: bind the workspace directory to the **identical absolute path** inside the container, using `${localWorkspaceFolder}`. This is what makes compose bind mounts like `./:/app` work with Docker-outside-of-Docker, and keeps Claude's per-project state keyed the same inside and outside.
- `features`:
  - `ghcr.io/devcontainers/features/docker-outside-of-docker` — docker CLI + compose, mounts the host socket.
  - `ghcr.io/devcontainers/features/github-cli`.
  - `ghcr.io/anthropics/devcontainer-features/claude-code` — installs the CLI for the integrated terminal and adds the `anthropic.claude-code` extension. The VS Code panel bundles its own CLI anyway; this is for the terminal.
- `mounts`: `source=<VSCWS_CLAUDE_DIR>,target=/home/vscode/.claude,type=bind`. The source is substituted by `vscws new` from config (placeholder `__VSCWS_CLAUDE_DIR__`). If `~/.config/gh` exists on the host at generation time, it is also mounted to `/home/vscode/.config/gh` so the `gh` login is shared.
- `containerEnv`: `CLAUDE_CONFIG_DIR=/home/vscode/.claude`.
- `customizations.vscode.extensions`: `anthropic.claude-code`, `eamodio.gitlens`, `ms-azuretools.vscode-containers`.
- `remoteUser`: `vscode`. On Linux hosts VS Code and the devcontainer CLI remap this user's uid to the host user's uid by default, so files in the bind-mounted workspace keep correct ownership.

Generated object (platform dependent):

- Remote/Linux mode: `runArgs: ["--network=host"]`. Sibling containers' published ports are reachable at `localhost` inside the dev container; VS Code port forwarding to the Mac still works.
- Local/macOS mode: no host networking (Docker Desktop support for it is opt-in). Sibling containers are reached via `host.docker.internal:<port>`; documented in the README.
- `name`: workspace name.

## 8. Presets (v1)

Every preset is "latest stable at build time". Nothing is pinned. `vscws rebuild` moves everything forward.

- **go**
  - Feature `ghcr.io/devcontainers/features/go` with `version: latest`. Installs gopls, delve, and the standard tool set the Go extension expects.
  - golangci-lint: latest stable via its official install script in a `postCreateCommand` (or the feature's golangci-lint option if it supports `latest`; verified during implementation).
  - Extensions: `golang.go`.
- **java**
  - Feature `ghcr.io/devcontainers/features/java` with `version: latest` (newest GA), Temurin distribution, `installMaven: true`, `installGradle: true`, both `latest`. README documents how to pin an LTS instead.
  - Extensions: `vscjava.vscode-java-pack`.
- **cpp**
  - Dockerfile on top of the base image:
    - GCC toolchain, gdb, ninja, ccache, pkg-config, make from Ubuntu.
    - Latest stable LLVM (clang, clangd, clang-format, clang-tidy, lldb) from apt.llvm.org via its install script with no version argument.
    - Latest CMake from Kitware's apt repository.
  - Extensions: `llvm-vs-code-extensions.vscode-clangd`, `ms-vscode.cmake-tools`, `vadimcn.vscode-lldb`.
  - Sets `C_Cpp` IntelliSense off so clangd owns the language server if the user adds the Microsoft C++ extension later.

Adding a preset = new directory with a `devcontainer.json` (and optional `Dockerfile`) plus a `description` field the `presets` command prints.

## 9. Claude Code sharing model

- Panel: the `anthropic.claude-code` extension is a workspace extension, so VS Code installs it into each container automatically. It bundles its own CLI, so the panel needs nothing from the host except the config directory.
- Login and state: the host's Claude config directory is bind-mounted into every container, and `CLAUDE_CONFIG_DIR` points at it. Credentials, `.claude.json` (OAuth account, project trust), settings, plugins, memory and history are therefore shared by the host and all containers. One login total on Linux. One extra login (from the first container) on macOS because of Keychain.
- Terminal: the official feature installs `claude` in the image for use in the integrated terminal. Auto-update inside containers is left enabled; updates are lost on rebuild, which is harmless.
- Concurrency: multiple simultaneous sessions on one subscription are normal usage. No repeated logins occur, so there is nothing that looks like abuse.

## 10. Docker for the project's own containers

- Docker-outside-of-Docker: the dev container has the docker CLI and the host's socket. `docker compose up` in the VS Code terminal runs on the host daemon. Images are cached once for all workspaces, no extra daemon, no privileged container.
- Works from the VS Code terminal inside the container. No separate SSH session or host terminal needed.
- Because the workspace is mounted at the identical path, relative bind mounts in compose files resolve correctly.
- Trade-offs accepted: socket access equals root on the host (personal dev machine); ports are shared across workspaces in remote mode (same as developing on the host).

## 11. Extensions policy

- Container extensions come only from the merged preset list.
- The Mac settings snippet sets `dev.containers.defaultExtensions` and `remote.SSH.defaultExtensions` to empty lists so nothing else is auto-installed. VS Code never copies the laptop's installed extensions to a remote on its own.
- UI-only extensions (themes, keymaps) keep running on the Mac, which is correct.

## 12. Git and GitHub

- Recommended: SSH key stays on the Mac; the SSH agent is forwarded through Remote-SSH into the VM and from there into the container by VS Code. `git push` works everywhere, no keys copied.
- VS Code copies `~/.gitconfig` into the container by default, so name and email carry over. `vscws setup` prompts for them if unset.
- Alternative documented in the README: `gh auth login` on the VM with a token, and `gh` inside the container.

## 13. README contents (bullet points, task oriented)

- Fresh machine: clone, `./bin/vscws setup`, re-login, verify with `vscws doctor`.
- Mac side: paste `mac/settings.json`, add SSH host entry, install Remote-SSH and Dev Containers extensions.
- Create a workspace, open it, reopen in container, first-time notes.
- Run your project's docker compose from the VS Code terminal.
- Update a language's configuration: edit `presets/<lang>/devcontainer.json`, run `vscws rebuild NAME` for existing workspaces (or regenerate with `vscws new`).
- Update tool versions: `vscws rebuild NAME`.
- Add a new preset.
- Claude: how login sharing works, what to do on macOS the first time.
- GitHub: agent forwarding or `gh auth login`.
- Troubleshooting: docker group, port conflicts, `host.docker.internal` on Mac, low-RAM VM.

## 14. Error handling

- Every command validates its inputs and prints a one-line error and exit code 1: unknown preset, missing workspace, workspace exists, missing dependency (names the `vscws setup` step that installs it).
- `setup` never deletes anything. Files it changes are backed up under `~/.claude/backups/` or `~/.config/vscws/backups/` with a timestamp.
- `rm` requires the workspace name typed back unless `--force`.
- `set -euo pipefail` in every script; no partial writes (generate into a temp dir, then move).

## 15. Testing

- Unit-level: a `tests/` directory with bash tests (bats not required; plain scripts with assertions) covering: preset merge output, config parsing, `new` layout, `ls` parsing, error paths. Run against a temporary root.
- Integration on this VM: `vscws new` + `vscws build` + `vscws shell` for each preset; inside the container verify `go version`, `golangci-lint version`, `java -version`, `mvn -v`, `gradle -v`, `clang --version`, `cmake --version`, `docker ps` (socket works), `claude --version`, and that Claude reports the existing login (`claude auth status` or equivalent) without prompting.
- Host check after `setup`: a fresh login shell has `CLAUDE_CONFIG_DIR` set, `claude` still logged in.
- macOS: user tests. Code paths for macOS are kept small (package installs, mode default, no host networking).
- Known limit: this VM has 1.9 GB RAM. Builds are done one preset at a time; the setup script does not add swap, but the README notes how to if needed.

## 16. Open decisions confirmed with the user

- Tool name `vscws`. Setup is `vscws setup`, not a separate script.
- Latest stable everywhere; Java means latest GA, README shows how to pin LTS.
- Host Claude switches to `CLAUDE_CONFIG_DIR` layout with a backup and a fallback symlink.
- Docker-outside-of-Docker, host networking on Linux only.
- No per-workspace cache persistence in v1.
