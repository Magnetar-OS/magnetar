#!/usr/bin/env bash
# Magnetar's artwork is CC-BY-SA-4.0; the code around it is GPL. A package
# that ships artwork (tracked images, or the pre-rendered ASCII logo) must
# declare both, or what it installs is licensed as something its owner did
# not choose.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
fail=0; with_art=0

for d in "$M"/pkgbuilds/*/; do
  [[ -f $d/PKGBUILD ]] || continue
  name=$(basename "$d")
  art=$(git -C "$M" ls-files -- "pkgbuilds/$name" | grep -cE '\.(png|svg|jpg|jpeg|ans)$' || true)
  (( art > 0 )) || continue
  with_art=$((with_art + 1))
  info=$(cd "$d" && makepkg --printsrcinfo)
  grep -qxF $'\tlicense = CC-BY-SA-4.0' <<< "$info" \
    || { echo "FAIL: $name ships $art artwork files and does not declare CC-BY-SA-4.0"; fail=1; }
done
(( with_art >= 3 )) || { echo "FAIL: found artwork in only $with_art packages; the test is not looking in the right place"; fail=1; }

(( fail == 0 )) && echo PASS
exit "$fail"
