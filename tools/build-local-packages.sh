#!/usr/bin/env bash
#
# Build every Magnetar package into build/repo, ready for iso/sync.sh to serve
# over file://.
#
# Idempotent: a package already in the repository is skipped unless --force.
# The suite takes tens of minutes per application from cold, so re-running
# after one failure must not rebuild the six that worked.
#
#   tools/build-local-packages.sh [--force] [--only <name>]
#
# --nocheck throughout: whether the ISO boots is the question here, not whether
# the test suites pass. Checks run in CI against the pushed repositories.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$root/build/repo/x86_64"
status="$root/build/packages-status.txt"
force=0
only=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --force) force=1 ;;
    --only)  only="${2:-}"; shift ;;
    *) echo "build-local-packages: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$repo"
: > "$status"

_already() {
  compgen -G "$repo/$1-*.pkg.tar.zst" > /dev/null
}

_build() {
  local dir="$1" name="$2"
  if [[ -n $only && $name != "$only" ]]; then return 0; fi

  if (( ! force )) && _already "$name"; then
    printf '  %-18s skip (already built)\n' "$name"
    echo "$name SKIP" >> "$status"
    return 0
  fi

  printf '  %-18s building… ' "$name"
  local log="$root/build/log-$name.txt"
  if (cd "$dir" && makepkg -sf --noconfirm --nocheck --needed >"$log" 2>&1); then
    cp "$dir"/*.pkg.tar.zst "$repo/" 2>/dev/null
    echo "ok"
    echo "$name OK" >> "$status"
  else
    echo "FAILED (see build/log-$name.txt)"
    echo "$name FAILED" >> "$status"
    sed -n '/error\[\?E\?[0-9]*\]\?:/p;/^error:/p' "$log" | head -5 | sed 's/^/      /'
  fi
}

echo "==> configuration packages"
for p in magnetar-repos magnetar-settings magnetar-desktop magnetar-calamares; do
  _build "$root/pkgbuilds/$p" "$p"
done

echo "==> applications (local working trees)"
if [[ -d $root/build/pkgbuilds-local ]]; then
  for d in "$root"/build/pkgbuilds-local/*-git; do
    [[ -d $d ]] || continue
    _build "$d" "$(basename "$d")"
  done
else
  echo "  none — run tools/gen-app-pkgbuilds-local.sh first"
fi

echo
echo "==> repository index"
if compgen -G "$repo/*.pkg.tar.zst" > /dev/null; then
  ( cd "$repo" && repo-add -q -R magnetar.db.tar.zst ./*.pkg.tar.zst >/dev/null )
  echo "  $(find "$repo" -name '*.pkg.tar.zst' | wc -l) packages in $repo"
fi

echo
sort "$status" | awk '{print "  "$0}'
grep -q FAILED "$status" && exit 1
exit 0
