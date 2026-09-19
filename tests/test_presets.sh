#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$VSCWS")/.." && pwd -P)"

out="$("$VSCWS" --presets)"
for p in bun cpp go java js python; do
  assert_contains "$out" "$p"
done
assert_not_contains "$out" "_common"

# every preset and the common layer must be valid JSON with a description (presets only)
jq -e . "$REPO/presets/_common.json" >/dev/null
for d in "$REPO"/presets/*/; do
  f="$d/devcontainer.json"
  jq -e . "$f" >/dev/null || { echo "  invalid JSON: $f"; exit 1; }
  desc="$(jq -r '.description // ""' "$f")"
  [ -n "$desc" ] || { echo "  missing description: $f"; exit 1; }
  assert_contains "$out" "$desc"
done

# common layer contract
c="$REPO/presets/_common.json"
assert_eq "$(jq -r .image "$c")" "mcr.microsoft.com/devcontainers/base:ubuntu" "image"
assert_eq "$(jq -r .remoteUser "$c")" "vscode" "remoteUser"
assert_eq "$(jq -r '.containerEnv.CLAUDE_CONFIG_DIR' "$c")" "/home/vscode/.claude" "CLAUDE_CONFIG_DIR"
assert_eq "$(jq -r '.workspaceFolder' "$c")" '${localWorkspaceFolder}' "workspaceFolder"
assert_contains "$(jq -r '.mounts[]' "$c")" "source=__VSCWS_CLAUDE_DIR__,target=/home/vscode/.claude,type=bind"
for feat in docker-outside-of-docker github-cli node anthropics/devcontainer-features/claude-code; do
  assert_contains "$(jq -r '.features | keys[]' "$c")" "$feat"
done
assert_eq "$(jq -r '.features["ghcr.io/devcontainers/features/docker-outside-of-docker:1"].dockerDashComposeVersion' "$c")" "none" "docker-outside-of-docker compose version"
assert_contains "$(jq -r '.customizations.vscode.extensions[]' "$c")" "anthropic.claude-code"
assert_eq "$(jq -r '.customizations.vscode.settings["chat.disableAIFeatures"]' "$c")" "true" "copilot disabled"
assert_eq "$(jq -r '.customizations.vscode.settings["github.copilot.enable"]["*"]' "$c")" "false" "copilot completions off"
assert_eq "$(jq -r '.customizations.vscode.settings["remote.autoForwardPortsSource"]' "$c")" "hybrid" "port forwarding hybrid"
echo "  ok"
