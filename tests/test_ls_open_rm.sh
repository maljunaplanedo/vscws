#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

# empty root
out="$("$VSCWS" ls)"
assert_contains "$out" "no workspaces"

"$VSCWS" new a1 --preset go >/dev/null
"$VSCWS" new b2 --preset java >/dev/null
mkdir -p "$VSCWS_ROOT/foreign"
out="$("$VSCWS" ls)"
assert_contains "$out" "a1"
assert_contains "$out" "go"
assert_contains "$out" "b2"
assert_contains "$out" "java"
assert_contains "$out" "foreign"

# open, remote mode: prints the laptop command
out="$("$VSCWS" open a1)"
assert_contains "$out" "code --folder-uri \"vscode-remote://ssh-remote+myvm$VSCWS_ROOT/a1\""
assert_contains "$out" "Reopen in Container"
if VSCWS_SSH_HOST= "$VSCWS" open a1 >/dev/null 2>"$TMP/err"; then echo "  expected failure without ssh host"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "VSCWS_SSH_HOST is not set"
assert_fails "$VSCWS" open nope

# open, local mode without a `code` binary on PATH: prints the folder
mkdir -p "$TMP/bin"; ln -s "$(command -v jq)" "$TMP/bin/jq"
for b in bash uname sed grep basename dirname date mktemp; do ln -sf "$(command -v $b)" "$TMP/bin/$b"; done
out="$(PATH="$TMP/bin" VSCWS_MODE=local "$VSCWS" open a1)"
assert_contains "$out" "$VSCWS_ROOT/a1"
assert_contains "$out" "Reopen in Container"

# rm: wrong name typed -> nothing deleted
if printf 'wrong\n' | "$VSCWS" rm a1 >/dev/null 2>"$TMP/err"; then echo "  expected abort"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "aborted"
[ -d "$VSCWS_ROOT/a1" ] || { echo "  a1 deleted on abort"; exit 1; }

# rm: correct name -> deleted
out="$(printf 'a1\n' | "$VSCWS" rm a1)"
assert_contains "$out" "deleted $VSCWS_ROOT/a1"
[ ! -e "$VSCWS_ROOT/a1" ] || { echo "  a1 still exists"; exit 1; }
assert_fails "$VSCWS" rm a1
echo "  ok"
