#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

# --- remote mode, go preset
out="$("$VSCWS" new proj1 --preset go)"
assert_contains "$out" "created $VSCWS_ROOT/proj1 (preset: go)"
f="$VSCWS_ROOT/proj1/.devcontainer/devcontainer.json"
[ -f "$f" ] || { echo "  missing $f"; exit 1; }
jq -e . "$f" >/dev/null
assert_eq "$(jq -r .name "$f")" "proj1" "name"
assert_eq "$(jq -r .image "$f")" "mcr.microsoft.com/devcontainers/base:ubuntu" "image"
assert_eq "$(jq -r '.description // "absent"' "$f")" "absent" "description stripped"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/go:1"].version' "$f")" "latest" "go feature"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/node:1"].version' "$f")" "lts" "node kept from common"
assert_contains "$(jq -r '.mounts[]' "$f")" "source=$VSCWS_CLAUDE_DIR,target=/home/vscode/.claude,type=bind"
assert_not_contains "$(cat "$f")" "__VSCWS_CLAUDE_DIR__"
assert_eq "$(jq -r '.runArgs | index("--network=host")' "$f")" "0" "host network in remote mode"
exts="$(jq -r '.customizations.vscode.extensions[]' "$f")"
assert_contains "$exts" "anthropic.claude-code"
assert_contains "$exts" "golang.go"
assert_eq "$(jq -r '.customizations.vscode.extensions | length' "$f")" \
          "$(jq -r '.customizations.vscode.extensions | unique | length' "$f")" "no duplicate extensions"
m="$VSCWS_ROOT/proj1/.vscws.json"
assert_eq "$(jq -r .preset "$m")" "go" "marker preset"
assert_eq "$(jq -r .name "$m")" "proj1" "marker name"
assert_eq "$(jq -r .vscws "$m")" "0.1.0" "marker version"
[ -n "$(jq -r .created "$m")" ]

# no temp dirs left behind
assert_eq "$(ls -a "$VSCWS_ROOT" | grep -c 'vscws-tmp' || true)" "0" "no temp leftovers"

# --- local mode: no host networking
VSCWS_MODE=local "$VSCWS" new proj2 --preset go >/dev/null
f2="$VSCWS_ROOT/proj2/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.runArgs // "absent"' "$f2")" "absent" "no runArgs in local mode"

# --- errors
assert_fails "$VSCWS" new proj1 --preset go           # exists
[ -d "$VSCWS_ROOT/proj1" ]
assert_fails "$VSCWS" new "bad name" --preset go
assert_fails "$VSCWS" new .hidden --preset go
assert_fails "$VSCWS" new -x --preset go
assert_fails "$VSCWS" new proj3 --preset nope
[ ! -e "$VSCWS_ROOT/proj3" ]
assert_fails "$VSCWS" new proj3
assert_fails "$VSCWS" new --preset go
assert_fails "$VSCWS" new proj3 --preset go --bogus
assert_eq "$(ls -a "$VSCWS_ROOT" | grep -c 'vscws-tmp' || true)" "0" "no temp leftovers after errors"

# --- unset root, non-interactive: clear error
if VSCWS_ROOT= "$VSCWS" new proj4 --preset go </dev/null >/dev/null 2>"$TMP/err"; then echo "  expected failure"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "VSCWS_ROOT is not set"

# --- config file is honoured when env is unset
mkdir -p "$TMP/cfgroot"
printf "VSCWS_ROOT='%s'\nVSCWS_CLAUDE_DIR='/x/claude'\n" "$TMP/cfgroot" > "$VSCWS_CONFIG"
VSCWS_ROOT= VSCWS_CLAUDE_DIR= "$VSCWS" new proj5 --preset go >/dev/null
assert_contains "$(jq -r '.mounts[]' "$TMP/cfgroot/proj5/.devcontainer/devcontainer.json")" "source=/x/claude,"

# --- dotfiles in a preset directory are copied too (no dotglob in bash 3.2)
repo_presets="$(dirname "$VSCWS")/../presets"
cp -R "$repo_presets" "$TMP/presets"
printf 'build/\n*.log\n' > "$TMP/presets/go/.dockerignore"
VSCWS_PRESETS_DIR="$TMP/presets" "$VSCWS" new dotp --preset go >/dev/null
di="$VSCWS_ROOT/dotp/.devcontainer/.dockerignore"
[ -f "$di" ] || { echo "  missing $di"; exit 1; }
assert_eq "$(cat "$di")" "build/
*.log" "dotfile copied from preset"

# --- Dockerfile presets: Dockerfile copied, image dropped, build kept
for p in cpp bun python; do
  "$VSCWS" new "w-$p" --preset "$p" >/dev/null
  d="$VSCWS_ROOT/w-$p/.devcontainer"
  [ -f "$d/Dockerfile" ] || { echo "  $p: Dockerfile not copied"; exit 1; }
  assert_eq "$(jq -r '.image // "absent"' "$d/devcontainer.json")" "absent" "$p: image dropped"
  assert_eq "$(jq -r '.build.dockerfile' "$d/devcontainer.json")" "Dockerfile" "$p: build.dockerfile"
  grep -q '^FROM mcr.microsoft.com/devcontainers/base:ubuntu' "$d/Dockerfile" || { echo "  $p: wrong base image"; exit 1; }
done

# --- js: node feature options merged, not replaced
"$VSCWS" new w-js --preset js >/dev/null
fj="$VSCWS_ROOT/w-js/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/node:1"].version' "$fj")" "lts" "js keeps lts"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/node:1"].pnpmVersion' "$fj")" "latest" "js adds pnpm"
assert_contains "$(jq -r '.customizations.vscode.extensions[]' "$fj")" "dbaeumer.vscode-eslint"

# --- python: no python feature (uv-managed prebuilt Python instead), plus Dockerfile
fp="$VSCWS_ROOT/w-python/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.features | has("ghcr.io/devcontainers/features/python:1")' "$fp")" "false" "python feature absent"
assert_contains "$(jq -r '.customizations.vscode.extensions[]' "$fp")" "charliermarsh.ruff"

# --- cpp: clangd and cmake tools
fc="$VSCWS_ROOT/w-cpp/.devcontainer/devcontainer.json"
assert_contains "$(jq -r '.customizations.vscode.extensions[]' "$fc")" "llvm-vs-code-extensions.vscode-clangd"
assert_contains "$(jq -r '.customizations.vscode.extensions[]' "$fc")" "ms-vscode.cmake-tools"

echo "  ok"
