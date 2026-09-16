#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

out="$("$VSCWS" --version)"
assert_contains "$out" "vscws 0.1.0"

# no arguments: usage on stderr, exit 1
if "$VSCWS" >/dev/null 2>"$TMP/err"; then echo "  expected exit 1"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "Usage: vscws"

# unknown command
if "$VSCWS" bogus >/dev/null 2>"$TMP/err"; then echo "  expected exit 1"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "vscws: unknown command 'bogus'"

# help on stdout, exit 0
out="$("$VSCWS" --help)"
assert_contains "$out" "new NAME --preset P"
echo "  ok"
