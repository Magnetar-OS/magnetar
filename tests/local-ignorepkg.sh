#!/usr/bin/env bash
# The IgnorePkg example in 99-local.conf, uncommented, must take effect when the
# file is included after the repository sections, as pacman.conf does.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d); mkdir -p "$w/d"
# Uncomment the example: the lines after "If you add an IgnorePkg" that are
# indented config ("#   [options]", "#   IgnorePkg = foo"), leaving prose alone.
sed -nE 's/^#   (\[options\]|IgnorePkg = .*)$/\1/p' "$R/repos.d/99-local.conf" > "$w/d/99-local.conf"
grep -q IgnorePkg "$w/d/99-local.conf" || { echo "FAIL: no IgnorePkg example found"; exit 1; }
sed -n '/^\[options\]/,/^SigLevel/p' "$R/pacman.conf" | grep -vE '^(HoldPkg|DownloadUser)' > "$w/pacman.conf"
printf '\n[core]\nServer = https://example.invalid/$repo\n\nInclude = %s/d/*.conf\n' "$w" >> "$w/pacman.conf"
out=$(pacman-conf --config "$w/pacman.conf" IgnorePkg 2>&1)
rm -rf "$w"
[[ $out == foo ]] || { echo "FAIL: pacman-conf said: $out"; exit 1; }
echo PASS
