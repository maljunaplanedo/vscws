# Sourced by every test. Isolates the tool from the real home.
set -euo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export VSCWS_CLAUDE_DIR="$TMP/claude"
VSCWS="${VSCWS_BIN:-$(cd "$(dirname "$0")/.." && pwd -P)/bin/vscws}"

assert_eq() {  # actual expected label
  if [ "$1" != "$2" ]; then echo "  assert_eq failed ($3): expected '$2', got '$1'"; exit 1; fi
}
assert_contains() {  # haystack needle
  case "$1" in *"$2"*) ;; *) echo "  assert_contains failed: '$2' not found in:"; echo "$1"; exit 1 ;; esac
}
assert_not_contains() {  # haystack needle
  case "$1" in *"$2"*) echo "  assert_not_contains failed: '$2' found in:"; echo "$1"; exit 1 ;; esac
}
assert_fails() {  # cmd...
  if "$@" >/dev/null 2>&1; then echo "  expected failure but succeeded: $*"; exit 1; fi
}
