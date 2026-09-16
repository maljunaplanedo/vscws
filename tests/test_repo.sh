#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

mkrepo() {  # dir  [with-devcontainer]
  mkdir -p "$1" && cd "$1"
  git init -q && git -c user.name=t -c user.email=t@t config commit.gpgsign false
  echo "hello" > README.md
  if [ "${2:-}" = yes ]; then mkdir .devcontainer && echo '{"name":"old"}' > .devcontainer/devcontainer.json; fi
  git add -A && git -c user.name=t -c user.email=t@t commit -qm init
  cd - >/dev/null
}

mkrepo "$TMP/src1"
"$VSCWS" new r1 --preset go --repo "$TMP/src1" >/dev/null
[ -f "$VSCWS_ROOT/r1/README.md" ] || { echo "  clone missing"; exit 1; }
[ -d "$VSCWS_ROOT/r1/.git" ] || { echo "  .git missing"; exit 1; }
assert_eq "$(jq -r .name "$VSCWS_ROOT/r1/.devcontainer/devcontainer.json")" "r1" "generated over clone"

# repo already has .devcontainer: answer n -> abort, nothing created
mkrepo "$TMP/src2" yes
if printf 'n\n' | "$VSCWS" new r2 --preset go --repo "$TMP/src2" >/dev/null 2>"$TMP/err"; then echo "  expected abort"; exit 1; fi
assert_contains "$(cat "$TMP/err")" "aborted"
[ ! -e "$VSCWS_ROOT/r2" ] || { echo "  r2 should not exist"; exit 1; }

# answer y -> overwritten
printf 'y\n' | "$VSCWS" new r3 --preset go --repo "$TMP/src2" >/dev/null
assert_eq "$(jq -r .name "$VSCWS_ROOT/r3/.devcontainer/devcontainer.json")" "r3" "overwritten"

# bad URL: fails, nothing left behind
assert_fails "$VSCWS" new r4 --preset go --repo "$TMP/does-not-exist"
[ ! -e "$VSCWS_ROOT/r4" ]
assert_eq "$(ls -a "$VSCWS_ROOT" | grep -c 'vscws-tmp' || true)" "0" "no temp leftovers"
echo "  ok"
