#!/usr/bin/env bash
#
# Is [magnetar] serving every distribution package at the version this commit's
# PKGBUILDs declare?
#
# The ISO installs those packages from the published repository, so an ISO
# built before they are there carries the previous versions and says nothing
# about it. Publishing is a push to arch-repo followed by a GitHub Pages
# deployment, which finishes minutes after the Packages workflow does — so
# "Packages succeeded" is not yet "the repository serves them". This asks the
# repository itself, and can wait for it.
#
#   tools/check-published.sh [--wait SECONDS] [repository URL]
#
# Exit codes: 0 every version is served, 1 some are not (each is named),
# 2 could not run.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

wait_for=0
url="$DISTRO_REPO_URL"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) [[ $# -ge 2 ]] || { echo "check-published: --wait needs a number of seconds" >&2; exit 2; }
            wait_for=$2; shift 2 ;;
    -*)     echo "usage: check-published.sh [--wait SECONDS] [repository URL]" >&2; exit 2 ;;
    *)      url=$1; shift ;;
  esac
done
db="$url/x86_64/$DISTRO_REPO_NAME.db"

# name-pkgver-pkgrel of every PKGBUILD here: the database's entry names.
# Sourced rather than read with makepkg --printsrcinfo, which refuses to run
# as root, and the ISO job is root.
want=()
for p in "$root"/pkgbuilds/*/PKGBUILD; do
  want+=("$(bash -c 'source "$1" >/dev/null 2>&1; printf "%s-%s-%s" "$pkgname" "$pkgver" "$pkgrel"' _ "$p")")
done
[[ ${#want[@]} -gt 0 ]] || { echo "check-published: no PKGBUILDs under $root/pkgbuilds" >&2; exit 2; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
deadline=$(( SECONDS + wait_for ))
while :; do
  missing=()
  if curl -fsSL -o "$w/db" "$db" 2> "$w/err"; then
    bsdtar -tf "$w/db" | sed -n 's|/desc$||p' > "$w/served"
    for v in "${want[@]}"; do
      grep -qxF -- "$v" "$w/served" || missing+=("$v")
    done
    [[ ${#missing[@]} -gt 0 ]] || { echo "[$DISTRO_REPO_NAME] at $url serves all ${#want[@]} distribution packages at this commit's versions."; exit 0; }
    state="not served yet: ${missing[*]}"
  else
    state="could not fetch $db: $(tr '\n' ' ' < "$w/err")"
  fi
  (( SECONDS < deadline )) || break
  echo "waiting — $state"
  sleep 20
done

echo "check-published: $state" >&2
echo "  An ISO built now would carry whatever [$DISTRO_REPO_NAME] serves instead. Wait for the" >&2
echo "  Packages workflow to publish them (a changed package needs its pkgrel bumped)." >&2
exit 1
