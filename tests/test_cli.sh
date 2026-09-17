#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

out="$("$VSCWS" --version)"
assert_contains "$out" "vscws 0.2.0"

# no arguments: usage on stderr, exit 1
if "$VSCWS" >/dev/null 2>"$TMP/err"; then echo "  expected exit 1"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "Usage: vscws"

# unknown option
if "$VSCWS" --bogus >/dev/null 2>"$TMP/err"; then echo "  expected exit 1"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "vscws: unknown option"

# help on stdout, exit 0
out="$("$VSCWS" --help)"
assert_contains "$out" "--preset"

# DIR without --preset fails
assert_fails "$VSCWS" "$TMP/somedir"

# --preset without DIR fails
assert_fails "$VSCWS" --preset go

# unknown preset fails, creates no .devcontainer
d="$TMP/d"
if "$VSCWS" "$d" --preset nope >/dev/null 2>"$TMP/err"; then echo "  expected exit 1"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "unknown preset"
[ ! -e "$d/.devcontainer" ] || { echo "  .devcontainer should not exist"; exit 1; }

# -- ends option parsing, so a DIR starting with "-" works
dashdir="$TMP/-dashdir"
"$VSCWS" --preset go -- "$dashdir" >/dev/null
[ -f "$dashdir/.devcontainer/devcontainer.json" ] || { echo "  DIR starting with '-' did not generate"; exit 1; }

echo "  ok"
