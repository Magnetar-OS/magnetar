#!/usr/bin/env bash
# iso/sync.sh against the real upstream: it builds from the pinned commit,
# every patch applies, a second run yields the same tree, and the ISO build's
# pacman.conf orders [magnetar] above [cachyos] like the installed system
# (docs/REPOS.md). Needs network.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/no-local-repo"
export MAGNETAR_ISO_WORK="$w/iso-src" MAGNETAR_LOCAL_REPO="$w/no-local-repo"

"$M/iso/sync.sh" > "$w/first.log" 2>&1 || { echo "FAIL: sync.sh"; tail -20 "$w/first.log"; exit 1; }
cp -a "$w/iso-src" "$w/first"
"$M/iso/sync.sh" > "$w/second.log" 2>&1 || { echo "FAIL: second sync.sh"; tail -20 "$w/second.log"; exit 1; }

fail=0
diff -r --no-dereference --exclude=.git "$w/first" "$w/iso-src" > "$w/diff" || { echo "FAIL: a second run changes the tree:"; head -20 "$w/diff"; fail=1; }

# shellcheck source=/dev/null
. "$M/branding.env"
[[ $UPSTREAM_ISO_REF =~ ^[0-9a-f]{40}$ ]] || { echo "FAIL: UPSTREAM_ISO_REF is not a commit: $UPSTREAM_ISO_REF"; fail=1; }
[[ $(git -C "$w/iso-src" rev-parse HEAD) == "$UPSTREAM_ISO_REF" ]] || { echo "FAIL: the tree is not at the pinned commit"; fail=1; }

conf="$w/iso-src/archiso/pacman.conf"
mapfile -t repos < <(sed -n 's/^\[\([^]]*\)\]$/\1/p' "$conf" | grep -vx options)
order=" ${repos[*]} "
[[ $order == *" magnetar cachyos "* ]] || { echo "FAIL: ISO build repo order: ${repos[*]}"; fail=1; }

(( fail == 0 )) && echo PASS
exit "$fail"
