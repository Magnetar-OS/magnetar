#!/usr/bin/env bash
# The live ISO and an installed system must describe themselves the same way:
# the overlay's /etc/os-release must already be what magnetar-branding's hook
# script enforces, and LOGO=magnetar must resolve on an installed system —
# i.e. the icon ships in magnetar-branding, which every install has, not only
# in the installer package.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
B="$M/pkgbuilds/magnetar-branding"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0

cp "$M/iso/overlay/archiso/airootfs/etc/os-release" "$w/os-release"
sed "s|/etc/os-release|$w/os-release|" "$B/magnetar-branding" > "$w/branding"
bash "$w/branding" os-release
diff -u "$M/iso/overlay/archiso/airootfs/etc/os-release" "$w/os-release" \
  || { echo "FAIL: magnetar-branding rewrites the ISO's os-release (above)"; fail=1; }

logo=$(sed -n 's/^LOGO=//p' "$M/iso/overlay/archiso/airootfs/etc/os-release")
(cd "$B" && BUILDDIR="$w/b" PKGDEST="$w/out" SRCDEST="$w/b" makepkg -f --nodeps >/dev/null 2>&1)
bsdtar -tf "$w"/out/magnetar-branding-*.pkg.tar.zst | grep -qx "usr/share/icons/hicolor/scalable/apps/$logo.svg" \
  || { echo "FAIL: magnetar-branding does not ship the $logo icon os-release names"; fail=1; }

(( fail == 0 )) && echo PASS
exit "$fail"
