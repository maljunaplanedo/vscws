# vscws

Creates a per-project VS Code dev container workspace from a language preset. One command, then "Reopen in Container".

- Each workspace is a directory under a root you choose. It is mounted into the container at the same path.
- The container has the language's tools, all at the latest stable version at build time.
- VS Code installs only the extensions listed in the preset.
- The Claude Code panel works in every container with one shared login.
- Your project's own `docker compose` runs from inside the container against the host Docker.

## 1. Prerequisites

### On the machine that runs Docker (Linux VM)

- Docker (official installer, any recent Ubuntu):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# log out and back in, then:
docker run --rm hello-world
```

- git and jq:

```bash
sudo apt-get update && sudo apt-get install -y git jq
```

- Claude Code (so the login can be shared into containers):

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude   # log in once
```

### On a Mac that runs Docker locally instead

```bash
brew install git jq
brew install --cask docker     # then launch Docker Desktop once
curl -fsSL https://claude.ai/install.sh | bash
```

### On the laptop with VS Code

- Install the Remote-SSH and Dev Containers extensions:

```bash
code --install-extension ms-vscode-remote.remote-ssh
code --install-extension ms-vscode-remote.remote-containers
```

- Add the contents of `mac/settings.json` to your VS Code user settings (Cmd+Shift+P → "Preferences: Open User Settings (JSON)"). This keeps laptop extensions out of the containers.
- Add the VM to `~/.ssh/config`:

```
Host myvm
    HostName <vm ip>
    User <vm user>
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
```

## 2. Install vscws

```bash
git clone <this repo url> ~/vscws
mkdir -p ~/.local/bin && ln -sf ~/vscws/bin/vscws ~/.local/bin/vscws
# make sure ~/.local/bin is on PATH, then:
vscws --version
```

- Config file `~/.config/vscws/config` (created on first `vscws new`, or write it yourself):

```bash
VSCWS_ROOT='/data/ws'        # where workspaces live
VSCWS_SSH_HOST='myvm'        # Host alias from the laptop's ~/.ssh/config (Linux VM only)
VSCWS_CLAUDE_DIR="$HOME/.claude"   # Claude config dir shared into containers
```

## 3. Share the Claude login with containers (Linux VM, optional)

- Claude keeps its login in two places: `~/.claude/` and the file `~/.claude.json`. Containers mount `~/.claude/`, so the file must live inside it.
- Safe to re-run (backs up first, leaves a symlink so nothing else breaks, skips work already done):

```bash
# safe to re-run: does nothing if already done
if [ -f ~/.claude.json ] && [ ! -L ~/.claude.json ]; then
  mkdir -p ~/.claude/backups && cp ~/.claude.json ~/.claude/backups/claude.json.$(date +%s)
  mv ~/.claude.json ~/.claude/.claude.json && ln -s ~/.claude/.claude.json ~/.claude.json
fi
grep -q 'CLAUDE_CONFIG_DIR' ~/.profile 2>/dev/null || printf '\nexport CLAUDE_CONFIG_DIR="$HOME/.claude"\n' >> ~/.profile
grep -q 'CLAUDE_CONFIG_DIR' ~/.bashrc 2>/dev/null || sed -i '1i export CLAUDE_CONFIG_DIR="$HOME/.claude"' ~/.bashrc
```

- Open a new shell and run `claude` to confirm you are still logged in.
- Skip this step if you prefer: the first container will ask you to log in once, and all containers share that login.
- On a Mac, skip it: the Mac keeps the login in Keychain. The first container asks for one login, shared by all containers after that.

## 4. Create and open a workspace

```bash
vscws presets                              # see what is available
vscws new myapi --preset go                # empty project
vscws new myapi2 --preset go --repo git@github.com:you/myapi.git  # or clone one
vscws open myapi                           # prints the command to run on the laptop
```

- On the laptop, run the printed `code --folder-uri ...` command. VS Code connects over SSH and asks "Reopen in Container". Click it.
- First open builds the image. Later opens take seconds.
- The Claude panel appears in the sidebar. The `claude` command also works in the VS Code terminal.
- On a Mac with local Docker, `vscws open` opens the folder directly.

## 5. Run your project's own Docker containers

- Open a terminal in VS Code (inside the dev container) and run `docker compose up` as usual. It runs on the host Docker.
- Relative bind mounts in compose files work because the workspace path is the same inside and outside.
- Linux VM: services published on a port are reachable at `localhost:<port>` from the dev container.
- Mac: use `host.docker.internal:<port>` instead of `localhost`.

## 6. Update a language configuration

- Edit `presets/<lang>/devcontainer.json` (features, extensions, settings) or `presets/<lang>/Dockerfile`.
- New workspaces pick it up immediately.
- Existing workspace: copy the changed file into its `.devcontainer/`, or edit `.devcontainer/devcontainer.json` there directly. Then in VS Code: Cmd+Shift+P → "Dev Containers: Rebuild Container".

## 7. Update tool and language versions

- Nothing is pinned. To move a workspace to the current latest stable of everything: Cmd+Shift+P → "Dev Containers: Rebuild Container Without Cache".
- To pin something instead, edit the preset, for example Java LTS: `"version": "25"` in the java feature.

## 8. Add a preset

- Create `presets/<name>/devcontainer.json` with a `"description"` and whatever `features`, `customizations.vscode.extensions`, `build` or `postCreateCommand` it needs.
- Optional `presets/<name>/Dockerfile` starting with `FROM mcr.microsoft.com/devcontainers/base:ubuntu`; then use `"build": { "dockerfile": "Dockerfile" }` in the json.
- Everything in `presets/_common.json` is merged in automatically. Arrays are concatenated, objects merged.
- Check it: `vscws presets`, then `bash tests/run.sh`.

## 9. Commands

```
vscws new NAME --preset P [--repo URL]   # create workspace NAME from preset P
vscws ls                                 # list workspaces
vscws presets                            # list available presets
vscws open NAME                          # print (or run) the VS Code command to open NAME
vscws rm NAME                            # delete workspace NAME (asks you to type the name)
```

## 10. Troubleshooting

- `permission denied` on docker: log out and in after `usermod -aG docker`.
- Port already in use on the VM: another workspace's stack uses it. Stop it or change the port.
- Claude asks to log in inside a container: on Linux do section 3; on Mac log in once, it is then shared.
- Build fails with out of memory on a small VM: add swap, `sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`.
- Slow first build: features download toolchains. Subsequent builds use the cache.
