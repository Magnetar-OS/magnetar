#!/usr/bin/env bash
# cutecosmic must stay pinned to the Qt build it was compiled against, yet
# accept CachyOS's optimised rebuilds of that same build: [cachyos-extra-v3]
# and [cachyos-extra-v4] carry qt6-base 6.11.2-3.1 for Arch's 6.11.2-3, and an
# exact "=6.11.2-3" made magnetar-desktop uninstallable on those CPUs.
set -euo pipefail
cd "$(dirname "$0")/../pkgbuilds/cutecosmic"
mapfile -t cons < <(makepkg --printsrcinfo | sed -nE 's/^\s*depends = qt6-base([<>=]+.*)$/\1/p')
[[ ${#cons[@]} -gt 0 ]] || { echo "FAIL: qt6-base is not version-constrained"; exit 1; }

# The pinned build: the version in the >= (or =) constraint.
pinned=$(printf '%s\n' "${cons[@]}" | sed -nE 's/^>?=(.*)$/\1/p' | head -n1)
[[ -n $pinned ]] || { echo "FAIL: no lower bound in: ${cons[*]}"; exit 1; }
pkgver=${pinned%-*}; rel=${pinned##*-}

satisfies() {  # does qt6-base $1 satisfy every constraint?
  local c op v r
  for c in "${cons[@]}"; do
    op=${c%%[0-9]*}; v=${c#"$op"}; r=$(vercmp "$1" "$v")
    case $op in
      '=')  (( r == 0 )) ;;
      '>=') (( r >= 0 )) ;;
      '<')  (( r < 0 )) ;;
      '<=') (( r <= 0 )) ;;
      '>')  (( r > 0 )) ;;
    esac || return 1
  done
}

fail=0
for ok in "$pinned" "$pkgver-$rel.1" "$pkgver-$rel.2"; do
  satisfies "$ok" || { echo "FAIL: rejects $ok (same Qt build)"; fail=1; }
done
for no in "$pkgver-$((rel + 1))" "$pkgver-$((rel - 1))" "${pkgver%.*}.$(( ${pkgver##*.} + 1 ))-1"; do
  satisfies "$no" && { echo "FAIL: accepts $no (a different Qt build)"; fail=1; }
done
(( fail == 0 )) && echo PASS
exit "$fail"
