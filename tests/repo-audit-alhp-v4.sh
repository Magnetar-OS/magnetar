#!/usr/bin/env bash
# magnetar-repo-audit must fail when ALHP (repositories named like
# [core-x86-64-v4]) is enabled alongside the CachyOS v4 set, as it does for the
# znver4 and v3 sets: both rebuild core/extra.
set -euo pipefail
A="$(cd "$(dirname "$0")/.." && pwd)/tools/repo-audit.sh"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/bin"
# pacman-conf: the repository list, and a signed SigLevel for every repo.
cat > "$w/bin/pacman-conf" <<'SH'
#!/bin/sh
case "$1" in
  --repo-list) printf '%s\n' cachyos-v4 cachyos-core-v4 cachyos-extra-v4 core-x86-64-v4 extra-x86-64-v4 magnetar cachyos core extra multilib ;;
  --repo=*) if [ "$2" = SigLevel ]; then echo Required; fi ;;
esac
exit 0
SH
# pacman: every database is empty.
printf '#!/bin/sh\nexit 0\n' > "$w/bin/pacman"
chmod +x "$w/bin/"*
rc=0; out=$(PATH="$w/bin:$PATH" MAGNETAR_REPO_OVERRIDES=/dev/null bash "$A" 2>&1) || rc=$?
grep -q 'ALHP and the CachyOS optimised repos are both enabled' <<<"$out" && [[ $rc -eq 1 ]] \
  || { echo "FAIL: rc=$rc"; printf '    %s\n' "$out"; exit 1; }
echo PASS
