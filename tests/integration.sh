#!/usr/bin/env bash
# Manual integration test: builds a workspace for PRESET with the devcontainer CLI and checks tools inside.
# Usage: tests/integration.sh PRESET   (needs docker and the devcontainer CLI)
set -euo pipefail
preset="${1:?usage: integration.sh PRESET}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
VSCWS="$HERE/../bin/vscws"
ws="${VSCWS_IT_ROOT:-$HOME/ws}/it-$preset"

cleanup() {
  ids="$(docker ps -aq --filter "label=devcontainer.local_folder=$ws" 2>/dev/null || true)"
  [ -n "$ids" ] && docker rm -f $ids >/dev/null
  rm -rf "$ws"
}

cleanup
"$VSCWS" "$ws" --preset "$preset"

devcontainer up --workspace-folder "$ws"
x() { devcontainer exec --workspace-folder "$ws" bash -lc "set -eo pipefail; $1"; }

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
  python) x 'python3 --version; uv --version; ruff --version; cd /tmp && rm -rf vscws-venv && uv venv vscws-venv && vscws-venv/bin/python -c "import sys, json; print(sys.version)" && rm -rf vscws-venv' ;;
  *) echo "no checks for $preset"; exit 1 ;;
esac
echo "== $preset OK"

cleanup
