#!/usr/bin/env bash
#
# Sign every package in build/repo and rebuild the database with signatures.
#
# [magnetar] is SigLevel = Required, so an unsigned package in the repository
# is a package nobody can install. This is the step between building and
# publishing, and it is separate from the build on purpose: building does not
# need the signing key, and most of what runs here should never see it.
#
#   tools/sign-packages.sh [--force]
#
# The passphrase comes from MAGNETAR_SIGNING_PASSPHRASE (set by
# ~/.config/magnetar/secrets.env). In CI it is a repository secret, alongside
# the exported private key.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

repo="$root/build/repo/x86_64"
fpr="382D984841F8C8A2BFB952675623FAF3DF36FFAF"
force=0
[[ ${1:-} == --force ]] && force=1

[[ -d $repo ]] || { echo "sign-packages: $repo does not exist" >&2; exit 2; }

if [[ -z ${MAGNETAR_SIGNING_PASSPHRASE:-} ]]; then
  echo "sign-packages: MAGNETAR_SIGNING_PASSPHRASE is not set." >&2
  echo "  Locally it comes from ~/.config/magnetar/secrets.env." >&2
  echo "  In CI it is a repository secret." >&2
  exit 2
fi

gpg --list-secret-keys "$fpr" >/dev/null 2>&1 || {
  echo "sign-packages: signing key $fpr is not in this keyring." >&2
  exit 2
}

signed=0 skipped=0
shopt -s nullglob
for pkg in "$repo"/*.pkg.tar.zst; do
  if [[ -f $pkg.sig && $force -eq 0 ]]; then
    skipped=$((skipped+1))
    continue
  fi
  rm -f "$pkg.sig"
  printf '%s\n' "$MAGNETAR_SIGNING_PASSPHRASE" \
    | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
          --local-user "$fpr" --detach-sign --output "$pkg.sig" "$pkg"
  printf '  signed  %s\n' "$(basename "$pkg")"
  signed=$((signed+1))
done

echo "signed=$signed already-signed=$skipped"

# -s signs the database itself; -v makes repo-add verify each package's
# signature as it indexes, so a bad signature fails here rather than on a
# user's machine.
echo "==> rebuilding the database, signed"
( cd "$repo"
  printf '%s\n' "$MAGNETAR_SIGNING_PASSPHRASE" \
    | GPGKEY="$fpr" repo-add -q -R -s -v -k "$fpr" \
        "$DISTRO_REPO_NAME.db.tar.zst" ./*.pkg.tar.zst
) || {
  echo "sign-packages: repo-add failed. If it could not reach the agent, run" >&2
  echo "  gpg-connect-agent updatestartuptty /bye" >&2
  exit 1
}

echo
ls -1 "$repo" | grep -E '\.(db|files)(\.tar\.zst)?(\.sig)?$' | sed 's/^/  /'
