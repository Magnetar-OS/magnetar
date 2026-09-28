#!/usr/bin/env bash
# magnetar-settings must keep every optdepends it declares (fastfetch, cutecosmic, the suite).
set -euo pipefail
cd "$(dirname "$0")/../pkgbuilds/magnetar-settings"
info=$(makepkg --printsrcinfo)
for want in fastfetch cutecosmic envelope circle slate locket; do
  grep -q "optdepends = $want:" <<<"$info" || { echo "FAIL: optdepends lost $want"; exit 1; }
done
echo PASS
