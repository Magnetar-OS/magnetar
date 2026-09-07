#!/usr/bin/env bash
#
# Regenerate magnetar-settings' system_actions from the installed COSMIC
# defaults, re-applying only the entries Magnetar redirects.
#
# Run this after a COSMIC update. Shipping a stale copy of a 26-entry map is
# how a distribution quietly loses a system action upstream added.
set -euo pipefail

SRC=/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions
DST="$(dirname "$0")/../pkgbuilds/magnetar-settings/skel/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions"

[[ -r $SRC ]] || { echo "regen: $SRC not found — is cosmic-settings-daemon installed?" >&2; exit 2; }

{
  sed -n '1,/^\/\/ Regenerate/p' "$DST" 2>/dev/null || true
} > /dev/null   # header is rewritten below, not preserved

{
  cat <<'HDR'
// Magnetar: COSMIC system actions.
//
// Generated from the cosmic-settings-daemon defaults, with two entries
// redirected. The whole map is shipped rather than a two-line override:
// cosmic-comp reads both the system file and this one, and shipping the
// complete map gives the same result whether it merges them or lets the
// local file win outright.
//
//   Launcher -> jump      (usage-weighted ranking, plugins, animation)
//   Terminal -> ghostty   (cosmic-term stays installed and usable)
//
// Regenerate against a newer COSMIC with tools/regen-system-actions.sh.
HDR
  sed -e 's|^\(\s*Launcher:\s*\)"cosmic-launcher",|\1"jump",|' \
      -e 's|^\(\s*Terminal:\s*\)"cosmic-term",|\1"ghostty",|' "$SRC"
} > "$DST"

before=$(grep -cE '^\s+[A-Za-z]+:' "$SRC")
after=$(grep -cE '^\s+[A-Za-z]+:' "$DST")
echo "system_actions regenerated: $after actions (upstream has $before)"
[[ $before == "$after" ]] || { echo "regen: action count changed — inspect before committing" >&2; exit 1; }
grep -E 'Launcher:|Terminal:' "$DST"
