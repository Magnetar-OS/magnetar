#!/usr/bin/env bash
#
# Verify every package in the ISO list resolves, with its dependencies, against
# the ISO's own pacman.conf — before mkarchiso runs.
#
# pacstrap fails on the first unresolvable name, tens of minutes into a build,
# with an error buried in mkarchiso output. This asks the same question in
# seconds. It is the difference between "you forgot to build locket" and an
# hour of confused log reading.
#
# It resolves against the pacman.conf iso/sync.sh generated, not this machine's:
# a host that has [magnetar] configured would otherwise vouch for names the
# ISO build (whose [magnetar] may be the local file:// repository) cannot see.
# Run iso/sync.sh first.
#
#   tools/check-iso-packages.sh [packages file] [pacman.conf]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

list="${1:-$root/iso/overlay/archiso/packages_${DISTRO_ID}.x86_64}"
conf="${2:-$root/build/iso-src/archiso/pacman.conf}"

[[ -r $list ]] || { echo "check-iso-packages: $list not found" >&2; exit 2; }
[[ -r $conf ]] || { echo "check-iso-packages: $conf not found; run iso/sync.sh first" >&2; exit 2; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/db"
# DownloadUser needs root to switch to; fakeroot only pretends to be root.
sed '/^DownloadUser/d' "$conf" > "$w/pacman.conf"

# Real databases in a throwaway dbpath: this machine's sync state is never
# touched. fakeroot because pacman refuses -Sy to a non-root user.
pac() { fakeroot pacman --config "$w/pacman.conf" --dbpath "$w/db" --noconfirm "$@"; }
pac -Sy >/dev/null

mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$list" | grep -v '^$')

if ! pac -Sp --print-format '%r/%n' "${pkgs[@]}" > "$w/resolved" 2> "$w/errors"; then
  echo "UNRESOLVABLE against $conf:"
  sed 's/^/  /' "$w/errors"
  echo
  echo "pacstrap would fail on these, well into the ISO build. Build them into"
  echo "build/repo (tools/build-local-packages.sh), or take them out of the list."
  exit 1
fi

echo "${#pkgs[@]} listed, $(wc -l < "$w/resolved") with dependencies; all resolvable against $conf"
awk -F/ '{print $1}' "$w/resolved" | sort | uniq -c | sort -rn | sed 's/^ */  /'
