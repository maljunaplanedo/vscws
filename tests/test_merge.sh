#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

existing_json='{"name":"custom","image":"my/image:1","customizations":{"vscode":{"extensions":["foo.bar","anthropic.claude-code"]}},"runArgs":["--privileged"]}'

setup() {  # writes a fresh $TMP/m/.devcontainer/devcontainer.json
  rm -rf "$TMP/m"
  mkdir -p "$TMP/m/.devcontainer"
  printf '%s' "$existing_json" > "$TMP/m/.devcontainer/devcontainer.json"
}

# --- (1) answer n -> abort, file unchanged, no temp dir
setup
f="$TMP/m/.devcontainer/devcontainer.json"
cp "$f" "$TMP/before.json"
if printf 'n\n' | "$VSCWS" "$TMP/m" --preset go >/dev/null 2>"$TMP/err"; then echo "  expected abort"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "aborted"
diff -q "$TMP/before.json" "$f" >/dev/null || { echo "  file changed on abort"; exit 1; }
assert_eq "$(ls -a "$TMP/m" | grep -c '.devcontainer.tmp' || true)" "0" "no temp dir after abort"

# --- (1b) abort path with a DIR name containing an apostrophe and a space:
# the cleanup trap must still find and remove its temp dir.
weird="$TMP/we'ird dir"
rm -rf "$weird"
mkdir -p "$weird/.devcontainer"
printf '%s' "$existing_json" > "$weird/.devcontainer/devcontainer.json"
if printf 'n\n' | "$VSCWS" "$weird" --preset go >/dev/null 2>"$TMP/err"; then echo "  expected abort"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "aborted"
assert_eq "$(ls -a "$weird" | grep -c '.devcontainer.tmp' || true)" "0" "no temp dir after abort (weird dir name)"

# --- (2) answer y -> merged, existing wins, arrays appended
setup
printf 'y\n' | "$VSCWS" "$TMP/m" --preset go >/dev/null
assert_eq "$(jq -r .name "$f")" "custom" "existing name wins"
assert_eq "$(jq -r .image "$f")" "my/image:1" "existing image wins"
assert_eq "$(jq -r '.build // "absent"' "$f")" "absent" "build absent when image present"
exts="$(jq -r '.customizations.vscode.extensions[]' "$f")"
assert_contains "$exts" "foo.bar"
assert_contains "$exts" "golang.go"
assert_eq "$(jq -r '[.customizations.vscode.extensions[] | select(. == "anthropic.claude-code")] | length' "$f")" "1" "anthropic.claude-code once"
args="$(jq -r '.runArgs[]' "$f")"
assert_contains "$args" "--privileged"
assert_contains "$args" "--network=host"
[ "$(jq -r '.features | has("ghcr.io/devcontainers/features/go:1")' "$f")" = "true" ] || { echo "  go feature missing"; exit 1; }
assert_contains "$(jq -r '.mounts[]' "$f")" "source=$VSCWS_CLAUDE_DIR,target=/home/vscode/.claude,type=bind"

# --- (3) existing has "image": merging a Dockerfile preset (cpp) must not leave an
# unreferenced Dockerfile behind, and must say so.
setup
out3="$(printf 'y\n' | "$VSCWS" "$TMP/m" --preset cpp)"
assert_eq "$(jq -r .image "$f")" "my/image:1" "cpp: image kept"
assert_eq "$(jq -r '.build // "absent"' "$f")" "absent" "cpp: build absent"
assert_contains "$out3" "not used"
[ ! -f "$TMP/m/.devcontainer/Dockerfile" ] || { echo "  Dockerfile should not have been copied"; exit 1; }

# --- (3b) existing has neither image nor build: merging cpp keeps build, copies the
# Dockerfile, and a second merge keeps the existing copy untouched.
rm -rf "$TMP/m3b"
mkdir -p "$TMP/m3b/.devcontainer"
printf '%s' '{"name":"nobuild"}' > "$TMP/m3b/.devcontainer/devcontainer.json"
f3b="$TMP/m3b/.devcontainer/devcontainer.json"
printf 'y\n' | "$VSCWS" "$TMP/m3b" --preset cpp >/dev/null
assert_eq "$(jq -r '.build.dockerfile' "$f3b")" "Dockerfile" "cpp: build kept when no image"
df="$TMP/m3b/.devcontainer/Dockerfile"
[ -f "$df" ] || { echo "  Dockerfile not copied"; exit 1; }
cp "$df" "$TMP/dockerfile-before"
out3b="$(printf 'y\n' | "$VSCWS" "$TMP/m3b" --preset cpp)"
assert_contains "$out3b" "kept existing"
diff -q "$TMP/dockerfile-before" "$df" >/dev/null || { echo "  Dockerfile changed on second merge"; exit 1; }

# --- (4) existing has build.dockerfile, no image: merge go -> build kept, image absent
rm -rf "$TMP/m4"
mkdir -p "$TMP/m4/.devcontainer"
printf '%s' '{"build":{"dockerfile":"Mine"}}' > "$TMP/m4/.devcontainer/devcontainer.json"
printf 'y\n' | "$VSCWS" "$TMP/m4" --preset go >/dev/null
f4="$TMP/m4/.devcontainer/devcontainer.json"
assert_eq "$(jq -r '.build.dockerfile' "$f4")" "Mine" "build.dockerfile kept"
assert_eq "$(jq -r '.image // "absent"' "$f4")" "absent" "image absent"

# --- (5) existing file is not plain JSON (has a comment) -> fails, file unchanged
setup
printf '%s\n' '// a comment' > "$f"
printf '{"name":"custom"}' >> "$f"
cp "$f" "$TMP/before5.json"
if printf 'y\n' | "$VSCWS" "$TMP/m" --preset go >/dev/null 2>"$TMP/err"; then echo "  expected failure"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "not a JSON object"
diff -q "$TMP/before5.json" "$f" >/dev/null || { echo "  file changed despite invalid JSON"; exit 1; }

# --- (5b) existing file is valid JSON but not an object (e.g. an array) -> fails, file unchanged
setup
printf '%s' '[]' > "$f"
cp "$f" "$TMP/before5b.json"
if printf 'y\n' | "$VSCWS" "$TMP/m" --preset go >/dev/null 2>"$TMP/err"; then echo "  expected failure"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "not a JSON object"
diff -q "$TMP/before5b.json" "$f" >/dev/null || { echo "  file changed despite non-object JSON"; exit 1; }

# --- (6) stdin /dev/null -> aborts
setup
if "$VSCWS" "$TMP/m" --preset go </dev/null >/dev/null 2>"$TMP/err"; then echo "  expected abort on empty stdin"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "aborted"

echo "  ok"
