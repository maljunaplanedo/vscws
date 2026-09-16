#!/usr/bin/env bash
# Runs every tests/test_*.sh in its own bash process. Exit 1 if any fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
export VSCWS_BIN="$HERE/../bin/vscws"
pass=0; fail=0
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t")"
  if bash "$t"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $t"; fi
done
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
