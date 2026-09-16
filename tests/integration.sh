#!/usr/bin/env bash
# Manual integration test: builds a workspace for PRESET with the devcontainer CLI and checks tools inside.
# Usage: tests/integration.sh PRESET   (needs docker, devcontainer CLI, and VSCWS_ROOT configured)
set -euo pipefail
preset="${1:?usage: integration.sh PRESET}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
VSCWS="$HERE/../bin/vscws"
name="it-$preset"
root="${VSCWS_ROOT:-$(. "$HOME/.config/vscws/config"; echo "$VSCWS_ROOT")}"
ws="$root/$name"

if [ -d "$ws" ]; then printf '%s\n' "$name" | "$VSCWS" rm "$name"; fi
"$VSCWS" new "$name" --preset "$preset"

devcontainer up --workspace-folder "$ws"
x() { devcontainer exec --workspace-folder "$ws" bash -lc "set -e; $*"; }

echo "== common"
x 'whoami; pwd; echo CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR'
x 'test "$(pwd)" = "'"$ws"'"'
x 'docker ps >/dev/null && echo docker-socket-ok'
x 'node --version; gh --version | head -1; claude --version'
x 'claude -p "reply with the single word ok" --max-turns 1'
x 'ls ~/.claude/.claude.json ~/.claude/.credentials.json'

echo "== $preset"
case "$preset" in
  go)     x 'go version; gopls version; dlv version | head -1; golangci-lint version' ;;
  java)   x 'java -version; mvn -v | head -1; gradle -v | grep Gradle' ;;
  cpp)    x 'gcc --version | head -1; clang --version | head -1; clangd --version; lldb --version; cmake --version | head -1; ninja --version; ccache --version | head -1' ;;
  js)     x 'node --version; npm --version; pnpm --version' ;;
  bun)    x 'bun --version; node --version' ;;
  python) x 'python3 --version; uv --version; ruff --version' ;;
  *) echo "no checks for $preset"; exit 1 ;;
esac
echo "== $preset OK"
