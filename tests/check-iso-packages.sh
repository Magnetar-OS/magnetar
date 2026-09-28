#!/usr/bin/env bash
# tools/check-iso-packages.sh must resolve the ISO list against the ISO's own
# pacman.conf, not the host's: a name only the host's repositories carry has
# to be reported, and a dependency the ISO's repositories lack too.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/repo" "$w/b"

mkpkg() {  # name, depends...
  local n=$1; shift
  mkdir -p "$w/b/$n"
  {
    echo "pkgname=$n"; echo "pkgver=1"; echo "pkgrel=1"; echo "arch=(any)"
    printf 'depends=('; [[ $# -eq 0 ]] || printf "'%s' " "$@"; echo ')'
    echo 'package() { :; }'
  } > "$w/b/$n/PKGBUILD"
  (cd "$w/b/$n" && PKGDEST="$w/repo" BUILDDIR="$w/b" makepkg -f --nodeps >/dev/null 2>&1)
}
mkpkg alpha
mkpkg beta alpha
mkpkg gamma not-in-any-repo
repo-add -q "$w/repo/isotest.db.tar.gz" "$w/repo"/*.pkg.tar.zst

printf '[options]\nArchitecture = auto\nDownloadUser = alpm\n[isotest]\nSigLevel = Never\nServer = file://%s\n' "$w/repo" > "$w/pacman.conf"

fail=0
printf 'alpha\nbeta  # comment\n' > "$w/good.list"
bash "$M/tools/check-iso-packages.sh" "$w/good.list" "$w/pacman.conf" > "$w/out" 2>&1 \
  || { echo "FAIL: a resolvable list was rejected:"; cat "$w/out"; fail=1; }

# pacman: on every host. The ISO's repositories do not carry it here.
printf 'alpha\npacman\n' > "$w/host-only.list"
if bash "$M/tools/check-iso-packages.sh" "$w/host-only.list" "$w/pacman.conf" > "$w/out" 2>&1; then
  echo "FAIL: a name only the host's repositories carry was accepted"; fail=1
fi

printf 'gamma\n' > "$w/dep.list"
if bash "$M/tools/check-iso-packages.sh" "$w/dep.list" "$w/pacman.conf" > "$w/out" 2>&1; then
  echo "FAIL: a package with an unresolvable dependency was accepted"; fail=1
fi

(( fail == 0 )) && echo PASS
exit "$fail"
