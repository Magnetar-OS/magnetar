#!/usr/bin/env bash
# The canonical pacman.conf, with its drop-ins, must parse without a single
# warning: pacman prints every one on every invocation.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d)
sed "s|^Include = /etc/pacman.d/magnetar-repos.d/\*.conf|Include = $R/repos.d/*.conf|" "$R/pacman.conf" > "$w/pacman.conf"
out=$(pacman-conf --config "$w/pacman.conf" --repo-list 2>&1 >/dev/null || true)
rm -rf "$w"
[[ -z $out ]] || { echo "FAIL: $out"; exit 1; }
echo PASS
