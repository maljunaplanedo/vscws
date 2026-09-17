# vscws — create per-project VS Code dev containers with shared Claude Code

Date: 2026-09-16
Status: draft for user review

Revised 2026-09-17: reduced to a single operation (user feedback: helper, not framework).

## 1. Goal

- One command writes a `.devcontainer/` into a project directory from a language preset, ready to "Reopen in Container" in VS Code.
- The container has the language's build tools. Versions resolve to the latest stable when the image is built.
- VS Code installs only the extensions the preset lists.
- The Claude Code panel works in every container through one shared login directory. No per-container login.
- Projects with their own Docker containers run from inside the dev container without Docker-in-Docker.
- Works on Linux (any recent Ubuntu, used over Remote-SSH) and macOS (Docker Desktop on the same Mac).
- A README lists what to install first, with the commands, and how to use, update and extend presets.

## 2. Scope boundary

`vscws` does one thing: writes a `.devcontainer/` into a project directory from a preset. It does not:

- install anything, change shell profiles, or configure git, GitHub, tmux or SSH;
- build images or manage containers (VS Code does that: "Reopen in Container", "Rebuild Container");
- persist caches across rebuilds, combine presets, or support Windows;
- keep a workspace root or config file, a marker file, or clone git repos; there is no list, remove or open command — `vscws` writes one `.devcontainer/` and stops.

The README covers prerequisites and host configuration as copy-paste code blocks.

## 3. Repository layout

```
vscws/
  README.md                  # bullet-point instructions
  bin/vscws                  # the tool, bash 3.2 compatible (macOS default bash)
  presets/
    _common.json             # merged into every preset
    cpp/devcontainer.json
    cpp/Dockerfile
    go/devcontainer.json
    java/devcontainer.json
    js/devcontainer.json
    bun/devcontainer.json
    bun/Dockerfile
    python/devcontainer.json
    python/Dockerfile
  mac/settings.json          # VS Code user settings snippet for the Mac
  tests/                     # plain bash tests
  docs/superpowers/specs/    # this spec
```

## 4. The `vscws` command

```
vscws DIR --preset NAME     # write DIR/.devcontainer/ from preset NAME
vscws --presets             # list presets (name + description)
vscws --version | --help
```

- `DIR`: any directory, created if missing, resolved to an absolute path. `name` in the generated json is `basename DIR` (§5).
- Environment: `VSCWS_CLAUDE_DIR` — host directory mounted into containers as Claude config. Default `~/.claude`. (`VSCWS_PRESETS_DIR` is a test-only override.)
- Merge rule: if `DIR/.devcontainer/devcontainer.json` already exists, vscws deep-merges the preset into it with the existing values winning on conflicts and arrays appended and de-duplicated, shows a `diff -u` of existing vs. merged, and asks `Merge into DIR/.devcontainer? [y/N]`; anything but y/yes aborts with nothing changed. Other preset files (e.g. `Dockerfile`) are copied only when absent in the target. If the existing file has `image`, the merged result drops `build`; if it has `build`, it drops `image`. If `DIR/.devcontainer` exists without a `devcontainer.json`, or the existing `devcontainer.json` is not plain JSON (comments), vscws fails with a clear message and changes nothing.
- Generation happens in a temp dir inside `DIR` (`DIR/.devcontainer.tmp.XXXXXX`) that is moved into place on success; a failure or abort leaves no temp dir behind.
- Runtime dependencies: bash 3.2+, `jq`. No config file, no workspace root, no marker file, no git, no docker dependency.
- Errors: one line `vscws: ...` on stderr, exit 1.

## 5. Generated `.devcontainer/`

`devcontainer.json` = deep-merge of `presets/_common.json`, then `presets/P/devcontainer.json`, then a small generated object, using `jq`. Objects merge recursively; `mounts`, `runArgs` and `customizations.vscode.extensions` arrays concatenate and de-duplicate. If the preset has a `Dockerfile` it is copied alongside and the merged `image` key is dropped in favour of the preset's `build` key.

`_common.json`:

- `image`: `mcr.microsoft.com/devcontainers/base:ubuntu` — tracks the latest Ubuntu LTS, user `vscode` uid 1000, multi-arch.
- `workspaceMount` and `workspaceFolder`: bind the workspace to the identical absolute path inside the container via `${localWorkspaceFolder}`. This makes compose bind mounts like `./:/app` work with the host daemon, and keeps Claude's per-project state keyed the same inside and outside.
- `features`:
  - `ghcr.io/devcontainers/features/docker-outside-of-docker:1` with `dockerDashComposeVersion: none` — docker CLI and the `docker compose` plugin from apt, mounts the host socket. The option skips the feature's extra standalone `docker-compose` download, which breaks when a new compose release changes its checksum file.
  - `ghcr.io/devcontainers/features/github-cli:1`.
  - `ghcr.io/devcontainers/features/node:1` with `version: lts`.
  - `ghcr.io/anthropics/devcontainer-features/claude-code:1` — `claude` for the integrated terminal and the `anthropic.claude-code` extension. The panel bundles its own CLI; this is for the terminal.
- `mounts`: `source=__VSCWS_CLAUDE_DIR__,target=/home/vscode/.claude,type=bind`. The placeholder is replaced by `vscws` with `VSCWS_CLAUDE_DIR`.
- `containerEnv`: `CLAUDE_CONFIG_DIR=/home/vscode/.claude`.
- `customizations.vscode.extensions`: `anthropic.claude-code`, `eamodio.gitlens`, `ms-azuretools.vscode-containers`.
- `remoteUser`: `vscode`. On Linux hosts the uid is remapped to the host user by default, so bind-mounted files keep correct ownership.

Generated object:

- `name`: `basename DIR`.
- Linux: `runArgs: ["--network=host"]` so sibling containers' published ports are reachable at `localhost` inside the dev container. VS Code port forwarding still works.
- macOS: no host networking (opt-in and beta in Docker Desktop). Siblings are reached at `host.docker.internal:<port>`, noted in the README.

## 6. Presets

Nothing pinned. VS Code "Rebuild Container Without Cache" moves everything to the current latest stable.

- **go**: feature `ghcr.io/devcontainers/features/go:1` with `version: latest`, `golangciLintVersion: latest`. Installs Go, gopls, delve, golangci-lint. Extension `golang.go`.
- **java**: feature `ghcr.io/devcontainers/features/java:1` with `version: latest`, `jdkDistro: tem`, `installMaven: true`, `mavenVersion: latest`, `installGradle: true`, `gradleVersion: latest`. No LTS keyword exists; README shows pinning a number. Extension `vscjava.vscode-java-pack`.
- **cpp**: Dockerfile `FROM mcr.microsoft.com/devcontainers/base:ubuntu`. GCC toolchain, gdb, ninja, ccache, pkg-config, make from Ubuntu. Latest stable LLVM (clang, clangd, clang-format, clang-tidy, lldb) from apt.llvm.org's script with no version argument. Latest CMake as the official binary tarball from Kitware's GitHub releases (the apt repo lags new Ubuntu codenames). Extensions `llvm-vs-code-extensions.vscode-clangd`, `ms-vscode.cmake-tools`, `vadimcn.vscode-lldb`.

- **js** (frontend, Node): Node LTS comes from the common layer. Adds pnpm through the node feature's `pnpmVersion: latest`. yarn is not installed; README shows how to add it. Extensions `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`.
- **bun** (small backend, tool or script): Dockerfile `FROM` the base image, installs Bun with its official installer (`https://bun.sh/install`, latest stable, no version argument) into `/usr/local`. Node LTS is still present from the common layer for tooling that needs it. Extensions `oven.bun-vscode`, `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`.
- **python**: Dockerfile installs uv and ruff with their official installers system-wide, then `uv python install --default` puts the latest stable prebuilt CPython (python-build-standalone) on PATH. No feature, no source build. Extensions `ms-python.python`, `charliermarsh.ruff`.

Adding a preset: new directory under `presets/` with `devcontainer.json` (plus optional `Dockerfile`) and a top-level `"description"` string that `vscws --presets` prints and `vscws` strips.

## 7. Claude sharing model

- The `anthropic.claude-code` extension is a workspace extension; VS Code installs it into each container. It bundles its own CLI.
- Each container mounts the host's Claude config directory and sets `CLAUDE_CONFIG_DIR` to it. Credentials, `.claude.json` (OAuth account, project trust), settings, plugins, memory and history are shared by the host and all containers.
- Linux host: to reuse the existing login with zero new logins, the host must also use the `CLAUDE_CONFIG_DIR` layout. The README gives the three commands: export the variable in the shell profile, move `~/.claude.json` into `~/.claude/`, leave a symlink behind. Optional; without it, the first container asks for one login and all containers share it.
- macOS host: credentials live in Keychain, which containers cannot read. First container asks for one login; all containers then share it. Host untouched.
- Multiple concurrent sessions on one subscription are normal usage. No repeated logins occur.

## 8. Project Docker containers

- Docker-outside-of-Docker: the dev container's docker CLI talks to the host daemon. `docker compose up` in the VS Code terminal inside the container behaves as if run on the host. No second terminal needed.
- Images are cached once for all workspaces. No privileged container, no extra daemon.
- Trade-offs: socket access equals root on the host (personal machine); on Linux, ports are shared across workspaces like on the host.

## 9. README contents (bullets, task oriented)

- **1. Prerequisites** with install commands in code blocks: Docker (Ubuntu: Docker's official script and docker group; macOS: Docker Desktop), git, jq, VS Code with Remote-SSH and Dev Containers extensions on the Mac (including the `mac/settings.json` paste and the `~/.ssh/config` entry), Claude Code on the host.
- **2. Install vscws**: clone, symlink `bin/vscws` into `~/.local/bin`, `vscws --version`; the only setting is the optional `VSCWS_CLAUDE_DIR` env var.
- **3. Share the Claude login with containers** (Linux host, optional): the three commands, verbatim.
- **4. Create a dev container**: `vscws --presets`, `vscws DIR --preset NAME`, what it writes, the merge behaviour when `.devcontainer/` already exists (existing values win, file reformatted, Dockerfile kept).
- **5. Open it in VS Code**: laptop `code --folder-uri ...` or `open 'vscode://...'`, then "Dev Containers: Reopen in Container"; Mac with local Docker just opens the folder; first open builds; Claude panel appears.
- **6. Run your project's own Docker**: from the VS Code terminal in the container. macOS note on `host.docker.internal`.
- **7. Update a language configuration**: edit `presets/<lang>/devcontainer.json` or `Dockerfile`; existing project: run `vscws DIR --preset NAME` again and accept the merge, or edit `.devcontainer/` directly; then "Rebuild Container".
- **8. Update tool versions**: "Dev Containers: Rebuild Container Without Cache".
- **9. Add a preset** (including the yarn bullet).
- **10. Troubleshooting**: docker group not applied, port conflicts, low-RAM VM, Claude asks to log in, cpp disk space.

## 10. Testing

- `tests/test_cli.sh`: `--version`, no-args usage, unknown option, `--help`, DIR without `--preset`, `--preset` without DIR, unknown preset creates nothing.
- `tests/test_presets.sh`: `--presets` lists all six with descriptions, every preset JSON valid, `_common.json` contract.
- `tests/test_generate.sh`: fresh generation (name, image, feature merges, mounts, host networking, extensions, no leftover temp dir), the macOS branch (no `runArgs`), a relative `DIR`, the three Dockerfile presets, dotfile copying via `VSCWS_PRESETS_DIR`, and the `.devcontainer` without `devcontainer.json` error.
- `tests/test_merge.sh`: abort on `n` (file unchanged, no temp dir), accept on `y` (existing wins, arrays appended, image/build kept consistent), a second merge that keeps an already-copied `Dockerfile` ("kept existing"), an existing `build.dockerfile` with no `image`, a non-JSON existing file (fails, unchanged), and an aborted merge on empty stdin.
- `tests/integration.sh PRESET`: builds one preset end to end with the `devcontainer` CLI (installed only for testing, not a tool dependency) and checks `go version`, `golangci-lint version`, `java -version`, `mvn -v`, `gradle -v`, `clang --version`, `cmake --version`, `node --version`, `pnpm --version`, `bun --version`, `python3 --version`, `uv --version`, `ruff --version`, `docker ps`, `claude --version`, and that Claude sees the shared login; cleans up its container and directory before and after a successful run.
- macOS: user tests.

## 11. Decisions confirmed with the user

- Tool name `vscws`; it only writes a `.devcontainer/` into a project directory. No setup script.
- Latest stable everywhere; Java means latest GA, README shows pinning.
- Docker-outside-of-Docker; host networking on Linux only.
- Claude login shared through the mounted config directory; host layout change is a documented manual step.
