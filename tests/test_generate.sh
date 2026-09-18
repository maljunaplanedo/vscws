#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$VSCWS")/.." && pwd -P)"

# --- basic generation: go preset
out="$("$VSCWS" "$TMP/p/myapi" --preset go)"
f="$TMP/p/myapi/.devcontainer/devcontainer.json"
[ -f "$f" ] || { echo "  missing $f"; exit 1; }
jq -e . "$f" >/dev/null
assert_eq "$(jq -r .name "$f")" "myapi" "name"
assert_eq "$(jq -r .image "$f")" "mcr.microsoft.com/devcontainers/base:ubuntu" "image"
assert_eq "$(jq -r '.description // "absent"' "$f")" "absent" "description stripped"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/go:1"].version' "$f")" "latest" "go feature"
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/node:1"].version' "$f")" "lts" "node kept from common"
assert_contains "$(jq -r '.mounts[]' "$f")" "source=$VSCWS_CLAUDE_DIR,target=/home/vscode/.claude,type=bind"
assert_not_contains "$(cat "$f")" "__VSCWS_CLAUDE_DIR__"
assert_eq "$(jq -r '.runArgs | index("--network=host")' "$f")" "0" "host network first on Linux"
exts="$(jq -r '.customizations.vscode.extensions[]' "$f")"
assert_contains "$exts" "anthropic.claude-code"
assert_contains "$exts" "golang.go"
assert_eq "$(jq -r '.customizations.vscode.extensions | length' "$f")" \
          "$(jq -r '.customizations.vscode.extensions | unique | length' "$f")" "no duplicate extensions"

# no temp dirs left behind
assert_eq "$(ls -a "$TMP/p/myapi" | grep -c '.devcontainer.tmp' || true)" "0" "no temp leftovers"

# --- macOS branch: no host networking
mkdir -p "$TMP/bin"
cat > "$TMP/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo Darwin
EOF
chmod +x "$TMP/bin/uname"
PATH="$TMP/bin:$PATH" "$VSCWS" "$TMP/p/mac1" --preset go >/dev/null
fmac="$TMP/p/mac1/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.runArgs // "absent"' "$fmac")" "absent" "no runArgs on macOS"

# --- relative DIR works
( cd "$TMP" && "$VSCWS" rel --preset js >/dev/null )
[ -f "$TMP/rel/.devcontainer/devcontainer.json" ] || { echo "  relative DIR did not generate"; exit 1; }

# --- Dockerfile presets: Dockerfile copied, image dropped, build kept
for p in cpp bun python; do
  "$VSCWS" "$TMP/p/w-$p" --preset "$p" >/dev/null
  d="$TMP/p/w-$p/.devcontainer"
  [ -f "$d/Dockerfile" ] || { echo "  $p: Dockerfile not copied"; exit 1; }
  assert_eq "$(jq -r '.image // "absent"' "$d/devcontainer.json")" "absent" "$p: image dropped"
  assert_eq "$(jq -r '.build.dockerfile' "$d/devcontainer.json")" "Dockerfile" "$p: build.dockerfile"
  grep -q '^FROM mcr.microsoft.com/devcontainers/base:ubuntu' "$d/Dockerfile" || { echo "  $p: wrong base image"; exit 1; }
done

# --- dotfiles in a preset directory are copied too (no dotglob in bash 3.2)
cp -R "$REPO/presets" "$TMP/presets"
printf 'build/\n*.log\n' > "$TMP/presets/go/.dockerignore"
VSCWS_PRESETS_DIR="$TMP/presets" "$VSCWS" "$TMP/p/dotp" --preset go >/dev/null
di="$TMP/p/dotp/.devcontainer/.dockerignore"
[ -f "$di" ] || { echo "  missing $di"; exit 1; }
assert_eq "$(cat "$di")" "build/
*.log" "dotfile copied from preset"

# --- .devcontainer exists without devcontainer.json -> fails
mkdir -p "$TMP/p/nodj/.devcontainer"
if "$VSCWS" "$TMP/p/nodj" --preset go >/dev/null 2>"$TMP/err"; then echo "  expected failure"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "has no devcontainer.json"

# --- DIR with an apostrophe and a space generates fine (cleanup trap must not
# mis-evaluate the path via string interpolation)
weird="$TMP/we'ird dir"
"$VSCWS" "$weird" --preset go >/dev/null
[ -f "$weird/.devcontainer/devcontainer.json" ] || { echo "  weird DIR name did not generate"; exit 1; }
assert_eq "$(jq -r .name "$weird/.devcontainer/devcontainer.json")" "$(basename "$weird")" "name from weird DIR"

# --- non-writable DIR: fails with a clear message (skip when running as root,
# which ignores permission bits)
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$TMP/nowrite"
  chmod 555 "$TMP/nowrite"
  if "$VSCWS" "$TMP/nowrite" --preset go >/dev/null 2>"$TMP/err"; then
    chmod 755 "$TMP/nowrite"
    echo "  expected failure on non-writable DIR"; exit 1
  fi
  assert_contains "$(cat "$TMP/err")" "cannot write"
  chmod 755 "$TMP/nowrite"
fi

# --- cpp: debugger and sanitizer friendly container options
"$VSCWS" "$TMP/secopt" --preset cpp >/dev/null
fs="$TMP/secopt/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.capAdd | index("SYS_PTRACE")' "$fs")" "0" "cpp capAdd SYS_PTRACE"
assert_eq "$(jq -r '.securityOpt | index("seccomp=unconfined")' "$fs")" "0" "cpp seccomp unconfined"
assert_eq "$(jq -r '.customizations.vscode.settings["clangd.fallbackFlags"][0]' "$fs")" "-std=c++23" "cpp clangd fallback std"
assert_eq "$(jq -r '.customizations.vscode.settings["cmake.configureOnOpen"]' "$fs")" "true" "cpp configure on open"
echo "  ok"
