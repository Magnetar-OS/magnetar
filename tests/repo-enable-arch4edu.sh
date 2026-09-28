#!/usr/bin/env bash
# `magnetar-repo enable arch4edu` on a fresh machine: the key is imported by
# fingerprint, so enabling must not require arch4edu-keyring, which lives only
# inside [arch4edu] itself.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d); mkdir -p "$w/bin" "$w/dropin"
cp "$R/repos.d/"*.conf "$w/dropin/"
sed "s|^DROPIN_DIR=.*|DROPIN_DIR=$w/dropin|" "$R/magnetar-repo" > "$w/magnetar-repo"
printf '#!/bin/sh\necho 0\n' > "$w/bin/id"
printf '#!/bin/sh\nexit 0\n' > "$w/bin/pacman-key"
# A fresh Magnetar machine: nothing installed, arch4edu-keyring in no enabled repo.
printf '#!/bin/sh\necho "error: target not found: $*" >&2\nexit 1\n' > "$w/bin/pacman"
chmod +x "$w/bin/"* "$w/magnetar-repo"
rc=0; PATH="$w/bin:$PATH" bash "$w/magnetar-repo" enable arch4edu >"$w/out" 2>&1 || rc=$?
enabled=$(grep -c '^\[arch4edu\]' "$w/dropin/71-arch4edu.conf" || true)
cat "$w/out" | sed 's/^/    /'; rm -rf "$w"
[[ $rc -eq 0 && $enabled -eq 1 ]] || { echo "FAIL: rc=$rc enabled=$enabled"; exit 1; }
echo PASS
