#!/usr/bin/env bash
# magnetar-repo's _toggle must act on the repository it is given, not on a
# `repo` variable that happens to be in its caller's scope (shellcheck SC2318:
# `local repo="$1" f="${FILES[$repo]}"` expands $repo before it is assigned).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/dropin"
cp "$R/repos.d/"*.conf "$w/dropin/"
# The script's definitions without its dispatch at the bottom.
sed -e "s|^DROPIN_DIR=.*|DROPIN_DIR=$w/dropin|" -e '/^case "\${1:-status}" in$/,$d' "$R/magnetar-repo" > "$w/lib.sh"
# shellcheck source=/dev/null
. "$w/lib.sh"
# shellcheck disable=SC2034 # read by _toggle's buggy expansion, which is the point
caller() { local repo=valve; _toggle orhun enable; }
caller
fail=0
grep -q '^\[orhun\]' "$w/dropin/63-orhun.conf" || { echo "FAIL: orhun was not enabled"; fail=1; }
grep -q '^\[valve\]' "$w/dropin/80-valve.conf" && { echo "FAIL: the caller's repo (valve) was toggled instead"; fail=1; }
(( fail == 0 )) && echo PASS
exit "$fail"
