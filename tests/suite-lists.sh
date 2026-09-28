#!/usr/bin/env bash
# The suite is named by hand in several places. Each must carry every app the
# installer's "Magnetar applications" group installs (docs: the nine apps),
# and the local ISO-test build must produce every package the ISO list names.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"

# The reference list: the installer's application group.
mapfile -t suite < <(awk '/^- name: "Magnetar applications"/ {g=1; next}
                          /^- name:/ {g=0}
                          g && /^[ \t]+- / {sub(/^[ \t]+- /, ""); print}' \
                          "$M/pkgbuilds/magnetar-calamares/modules/netinstall.yaml")
[[ ${#suite[@]} -ge 9 ]] || { echo "FAIL: the installer's application group has ${#suite[@]} apps"; exit 1; }

fail=0
check() {  # $1: where, rest: the names found there
  local where=$1 app; shift
  for app in "${suite[@]}"; do
    printf '%s\n' "$@" | grep -qx -- "$app" || { echo "FAIL: $where lacks $app"; fail=1; }
  done
}

mapfile -t desk < <(cd "$M/pkgbuilds/magnetar-desktop" && makepkg --printsrcinfo \
                    | sed -nE 's/^\s*optdepends = ([^:]+):.*/\1/p')
check "magnetar-desktop optdepends" "${desk[@]}"

mapfile -t iso < <(grep -v '^#' "$M/iso/overlay/archiso/packages_magnetar.x86_64")
check "the ISO package list" "${iso[@]}"

# The local ISO-test path (tools/gen-app-pkgbuilds-local.sh) builds apps.txt,
# under their released names, plus locket from its own PKGBUILD.
mapfile -t local_apps < <(grep -vE '^(#|$)' "$M/pkgbuilds/apps/apps.txt" \
                          | awk -F'|' '{print ($5 != "" ? $5 : $1)}'; echo locket)
check "apps.txt (local ISO-test builds)" "${local_apps[@]}"

# ...and tools/build-local-packages.sh must build every distribution package
# the ISO list names, since sync.sh points [magnetar] at that repository alone.
for p in $(printf '%s\n' "${iso[@]}" | grep -E '^(magnetar-|cutecosmic$)' | grep -vxF -f <(printf '%s\n' "${suite[@]}")); do
  grep -qw -- "$p" "$M/tools/build-local-packages.sh" \
    || { echo "FAIL: tools/build-local-packages.sh does not build $p"; fail=1; }
done

(( fail == 0 )) && echo PASS
exit "$fail"
