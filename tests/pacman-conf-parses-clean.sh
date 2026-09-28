#!/usr/bin/env bash
# The canonical pacman.conf, with its drop-ins, must parse without a single
# warning: pacman prints every one on every invocation. Every CPU rendering
# too, since that is what the installer writes.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/pacman.d"
# The mirrorlists the file includes, so the check does not depend on the host's.
for m in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
  # shellcheck disable=SC2016 # pacman expands $repo and $arch
  echo 'Server = https://example.invalid/$repo/$arch' > "$w/pacman.d/$m"
done
sed "s|^CANONICAL=.*|CANONICAL=$R/pacman.conf|" "$R/magnetar-pacman-conf" > "$w/mpc"

check() {  # $1: label; stdin: a pacman.conf
  sed -e "s|^Include = /etc/pacman.d/magnetar-repos.d/\*.conf|Include = $R/repos.d/*.conf|" \
      -e "s|^Include = /etc/pacman.d/|Include = $w/pacman.d/|" > "$w/pacman.conf"
  local out
  out=$(pacman-conf --config "$w/pacman.conf" --repo-list 2>&1 >/dev/null || true)
  [[ -z $out ]] || { echo "FAIL ($1): $out"; return 1; }
}

fail=0
check canonical < "$R/pacman.conf" || fail=1
for level in znver4 v4 v3 none; do
  MAGNETAR_CPU_LEVEL=$level bash "$w/mpc" | check "$level" || fail=1
done
(( fail == 0 )) && echo PASS
exit "$fail"
