# vscws

Writes a VS Code dev container config into a project directory from a language preset. One command, then "Reopen in Container".

- The container has the language's tools, all at the latest stable version at build time.
- VS Code installs only the extensions listed in the preset.
- The Claude Code panel works in every container with one shared login. Copilot and all built-in AI completions are disabled inside containers; AI help is only what you ask for in the Claude panel.
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

- If `code` is not found, run "Shell Command: Install 'code' command in PATH" from the VS Code command palette first.

- Add the contents of `mac/settings.json` to your VS Code user settings (Cmd+Shift+P → "Preferences: Open User Settings (JSON)"). This keeps laptop extensions out of the containers and stops VS Code from auto-installing Copilot into them.
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
git clone https://github.com/maljunaplanedo/vscws.git ~/vscws
mkdir -p ~/.local/bin && ln -sf ~/vscws/bin/vscws ~/.local/bin/vscws
# make sure ~/.local/bin is on PATH, then:
vscws --version
```

- The only setting is the optional `VSCWS_CLAUDE_DIR` environment variable (default `~/.claude`): the host directory shared into containers as the Claude config.

## 3. Share the Claude login with containers (Linux VM, optional)

- Claude keeps its login in two places: `~/.claude/` and the file `~/.claude.json`. Containers mount `~/.claude/`, so the file must live inside it.
- Safe to re-run (backs up first, leaves a symlink so nothing else breaks, skips work already done):

```bash
# safe to re-run: does nothing if already done
if [ -f ~/.claude.json ] && [ ! -L ~/.claude.json ] && [ ! -e ~/.claude/.claude.json ]; then
  mkdir -p ~/.claude/backups && cp ~/.claude.json ~/.claude/backups/claude.json.$(date +%s)
  mv ~/.claude.json ~/.claude/.claude.json && ln -s ~/.claude/.claude.json ~/.claude.json
fi
grep -q 'CLAUDE_CONFIG_DIR' ~/.profile 2>/dev/null || printf '\nexport CLAUDE_CONFIG_DIR="$HOME/.claude"\n' >> ~/.profile
[ -f ~/.bashrc ] && ! grep -q 'CLAUDE_CONFIG_DIR' ~/.bashrc && sed -i '1i export CLAUDE_CONFIG_DIR="$HOME/.claude"' ~/.bashrc; true
```

- Open a new shell and run `claude` to confirm you are still logged in.
- Skip this step if you prefer: the first container will ask you to log in once, and all containers share that login.
- On a Mac, skip it: the Mac keeps the login in Keychain. The first container asks for one login, shared by all containers after that.
- If `~/.claude/.claude.json` already exists (you logged in from a container first), nothing is moved and that login stays the shared one.

## 4. Create a dev container

```bash
vscws --presets                        # see what is available
vscws ~/projects/myapi --preset go     # write ~/projects/myapi/.devcontainer/ from the go preset
```

- Writes `.devcontainer/devcontainer.json`, plus a `Dockerfile` for presets that need one (cpp, bun, python).
- `DIR` is created if missing; the container's `name` is `basename DIR`.
- If `.devcontainer/devcontainer.json` already exists, vscws shows a diff and asks before merging: your existing values win over the preset's, arrays (extensions, mounts, runArgs, ...) are appended and de-duplicated, and the file is reformatted. A `Dockerfile` already present in the target is kept, never overwritten.
- If your existing `devcontainer.json` has comments (VS Code writes them by default), vscws refuses to merge. Remove the comments or merge by hand.

## 5. Open it in VS Code

- From the laptop, over Remote-SSH:

```bash
code --folder-uri "vscode-remote://ssh-remote+myvm/home/<user>/projects/myapi"
# or:
open 'vscode://vscode-remote/ssh-remote+myvm/home/<user>/projects/myapi'
```

- Then choose "Dev Containers: Reopen in Container" when VS Code asks.
- On a Mac with local Docker, just open the folder in VS Code and choose "Reopen in Container".
- First open builds the image. Later opens take seconds.
- The Claude panel appears in the sidebar. The `claude` command also works in the VS Code terminal.

## 6. Run your project's own Docker containers

- Open a terminal in VS Code (inside the dev container) and run `docker compose up` as usual. It runs on the host Docker.
- Relative bind mounts in compose files work because the workspace path is the same inside and outside.
- Linux VM: services published on a port are reachable at `localhost:<port>` from the dev container.
- Because of that host networking, VS Code auto-forwards only ports opened by processes started in its own terminal (`remote.autoForwardPortsSource: hybrid`, set by the preset). Anything else: Ports panel → "Forward a Port".
- Mac: use `host.docker.internal:<port>` instead of `localhost`.

## 7. Update a language configuration

- Edit `presets/<lang>/devcontainer.json` (features, extensions, settings) or `presets/<lang>/Dockerfile`.
- New dev containers pick it up immediately.
- Existing project: run `vscws DIR --preset <lang>` again and accept the merge, or edit `.devcontainer/` there directly. Then in VS Code: Cmd+Shift+P → "Dev Containers: Rebuild Container".

## 8. Update tool and language versions

- Nothing is pinned. To move a project to the current latest stable of everything: Cmd+Shift+P → "Dev Containers: Rebuild Container Without Cache".
- To pin something instead, edit the preset, for example Java LTS: `"version": "25"` in the java feature.

## 9. Add a preset

- Create `presets/<name>/devcontainer.json` with a `"description"` and whatever `features`, `customizations.vscode.extensions`, `build` or `postCreateCommand` it needs.
- Optional `presets/<name>/Dockerfile` starting with `FROM mcr.microsoft.com/devcontainers/base:ubuntu`; then use `"build": { "dockerfile": "Dockerfile" }` in the json.
- Everything in `presets/_common.json` is merged in automatically. Arrays are concatenated, objects merged.
- Check it: `vscws --presets`, then `bash tests/run.sh`.
- Need yarn in the js preset? add `"postCreateCommand": "npm install -g yarn"` to `presets/js/devcontainer.json`.

## 10. Remove a dev container

- Everything vscws wrote is `DIR/.devcontainer/`. Docker keeps the container and image separately. Remove what you no longer need, in this order.
- Close the VS Code window for that folder first (or Cmd+Shift+P → "Dev Containers: Reopen Folder Locally").
- Remove the container (VS Code labels it with the folder path):

```bash
docker rm -f $(docker ps -aq --filter "label=devcontainer.local_folder=/absolute/path/to/DIR")
```

- Remove the image. VS Code names it `vsc-<folder name>-<hash>`:

```bash
docker images "vsc-*"
docker rmi <image id>
```

- Remove the config, or the whole project:

```bash
rm -rf /absolute/path/to/DIR/.devcontainer   # keep the project, drop the dev container config
rm -rf /absolute/path/to/DIR                  # or delete the project entirely
```

- Optional, frees the most space: `docker builder prune -af` removes the build cache shared by all dev containers. Keep the `vscode` Docker volume; it holds the VS Code server used by every container.
- Alternative for the container and image: Cmd+Shift+P → "Dev Containers: Clean Up Dev Containers..." removes stopped containers and images whose folders no longer exist.

## 11. Troubleshooting

- ThreadSanitizer aborts with "unable to disable ASLR", or gdb/lldb warn about address space randomization: the container was created before the cpp preset gained `capAdd: SYS_PTRACE` and `securityOpt: seccomp=unconfined`. Run `vscws DIR --preset cpp` again, accept the merge, then "Rebuild Container".
- `permission denied` on docker: log out and in after `usermod -aG docker`.
- Port already in use on the VM: another project's stack uses it. Stop it or change the port.
- Claude asks to log in inside a container: on Linux do section 3; on Mac log in once, it is then shared.
- Build fails with out of memory on a small VM: add swap, `[ -e /swapfile ] || (sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile)`.
- Slow first build: features download toolchains. Subsequent builds use the cache.
- Building the cpp preset runs out of disk: its image is about 3 GB and the export step needs about twice that, so keep at least 6 GB free. Free space with:
  ```
  docker builder prune -af
  sudo journalctl --vacuum-size=200M
  ```
