#!/usr/bin/env bash
#
# Verify every package in the ISO list is resolvable before mkarchiso runs.
#
# pacstrap fails on the first unresolvable name, tens of minutes into a build,
# with an error buried in mkarchiso output. This asks the same question in two
# seconds. It is the difference between "you forgot to build locket" and an
# hour of confused log reading.
#
#   tools/check-iso-packages.sh [packages file] [local repo dir]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

list="${1:-$root/iso/overlay/archiso/packages_${DISTRO_ID}.x86_64}"
localrepo="${2:-$root/build/repo/x86_64}"

[[ -r $list ]] || { echo "check-iso-packages: $list not found" >&2; exit 2; }

# Names the local repository provides, including provides= entries.
declare -A local_have=()
if compgen -G "$localrepo/*.pkg.tar.zst" > /dev/null; then
  for f in "$localrepo"/*.pkg.tar.zst; do
    n=$(bsdtar -xOqf "$f" .PKGINFO 2>/dev/null | awk -F' = ' '/^pkgname/ {print $2; exit}')
    [[ -n ${n:-} ]] && local_have[$n]=1
    while read -r pv; do
      [[ -n ${pv:-} ]] && local_have[${pv%%[<>=]*}]=1
    done < <(bsdtar -xOqf "$f" .PKGINFO 2>/dev/null | awk -F' = ' '/^provides/ {print $2}')
  done
fi

# Every name the configured repositories provide, fetched once. Asking pacman
# per package means one query per name across every enabled repository, which
# on a machine with many repositories takes minutes; this takes a second.
declare -A repo_have=()
while read -r n; do
  [[ -n ${n:-} ]] && repo_have[$n]=1
done < <(pacman -Slq 2>/dev/null)

# provides= entries too, so a virtual name like `jump` resolves to jump-git.
while read -r pv; do
  [[ -n ${pv:-} ]] && repo_have[${pv%%[<>=]*}]=1
done < <(pacman -Sl 2>/dev/null | awk '{print $2}' | xargs -r pacman -Si 2>/dev/null | awk -F' : ' '/^Provides/ && $2 != "None" {print $2}' | tr ' ' '\n')

missing=() from_local=0 from_repos=0
while read -r pkg; do
  pkg="${pkg%%#*}"; pkg="${pkg// /}"
  [[ -n $pkg ]] || continue

  if [[ -n ${local_have[$pkg]:-} ]]; then
    from_local=$((from_local+1))
  elif [[ -n ${repo_have[$pkg]:-} ]]; then
    from_repos=$((from_repos+1))
  else
    missing+=("$pkg")
  fi
done < "$list"

echo "resolvable from configured repositories : $from_repos"
echo "resolvable from $localrepo : $from_local"

if (( ${#missing[@]} )); then
  echo
  echo "UNRESOLVABLE (${#missing[@]}):"
  printf '  %s\n' "${missing[@]}"
  echo
  echo "pacstrap would fail on these, well into the ISO build. Build them into"
  echo "$localrepo, or take them out of the package list."
  exit 1
fi

echo "all packages resolvable"
