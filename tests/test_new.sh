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
echo "  ok"
