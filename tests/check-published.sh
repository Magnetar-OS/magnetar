#!/usr/bin/env bash
# tools/check-published.sh gates the ISO build on [magnetar] serving this
# commit's distribution packages. It must pass on a database that has every
# PKGBUILD's name-pkgver-pkgrel, fail naming the package when one is a pkgrel
# behind (the ISO that was built with the previous installer), and fail when
# the database cannot be fetched at all.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0

mapfile -t entries < <(for p in "$M"/pkgbuilds/*/PKGBUILD; do
  (cd "$(dirname "$p")" && makepkg --printsrcinfo | awk '
     /^pkgbase = / {n=$3} /^\tpkgver = / {v=$3} /^\tpkgrel = / {r=$3} END {print n "-" v "-" r}')
done)
[[ ${#entries[@]} -ge 7 ]] || { echo "FAIL: found ${#entries[@]} PKGBUILDs"; exit 1; }

mkdb() {  # $1: repository directory, rest: entry names
  local dir=$1 e; shift
  mkdir -p "$dir/x86_64" "$w/tree"
  rm -rf "$w/tree"/*
  for e in "$@"; do mkdir "$w/tree/$e"; echo '%NAME%' > "$w/tree/$e/desc"; done
  # Entry names as repo-add writes them: name-ver-rel/desc, no leading "./".
  bsdtar -czf "$dir/x86_64/magnetar.db" -C "$w/tree" "$@"
}

mkdb "$w/current" "${entries[@]}" some-app-1.0.0-1
bash "$M/tools/check-published.sh" "file://$w/current" > "$w/out" 2>&1 \
  || { echo "FAIL: a repository serving every version was rejected:"; cat "$w/out"; fail=1; }

# One package a pkgrel behind: what [magnetar] looks like before a publish lands.
stale=("${entries[@]}")
behind="${entries[0]}"
rel="${behind##*-}"
stale[0]="${behind%-*}-$(( rel - 1 ))"
mkdb "$w/stale" "${stale[@]}"
if bash "$M/tools/check-published.sh" "file://$w/stale" > "$w/out" 2>&1; then
  echo "FAIL: a repository still serving ${stale[0]} was accepted"; fail=1
elif ! grep -qF -- "$behind" "$w/out"; then
  echo "FAIL: the missing version $behind is not named:"; cat "$w/out"; fail=1
fi

if bash "$M/tools/check-published.sh" "file://$w/no-such-repo" > "$w/out" 2>&1; then
  echo "FAIL: an unreachable repository was accepted"; fail=1
fi

(( fail == 0 )) && echo PASS
exit "$fail"
