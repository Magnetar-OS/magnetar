#!/usr/bin/env bash
#
# Publish built distribution packages to [magnetar]: stage them into a clone of
# arch-repo, sign, check the result the way a user's pacman would, and push.
# The publish job of .github/workflows/packages.yml runs this; it is a script
# so that tests/publish-packages.sh can run all of it against a throwaway
# repository and key.
#
#   ARCH_REPO_REMOTE=<git remote> tools/publish-packages.sh <dir of built *.pkg.tar.zst>
#
# Environment:
#   ARCH_REPO_REMOTE       the arch-repo git remote to clone and push (required)
#   LINUX_GPG_KEY_ID       signing key; default: the first secret key in the keyring
#   LINUX_GPG_PASSPHRASE   its passphrase
#
# Adds every built package whose exact filename is not already in [magnetar].
# A version is published once: to ship a change, bump pkgver or pkgrel.
# Rebuilding an unchanged PKGBUILD therefore publishes nothing, which is what
# makes the nightly run safe — and a configuration package whose contents
# changed without a bump fails the run instead of publishing nothing.
#
# It also finishes renames. A package that another package in the repository
# replaces (tools/repo-superseded.sh) is removed from the database and the
# tree, in both architectures: the app pipelines publish the new name and
# never touch the old one, which would otherwise stay installable for good.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

DIST="$(cd "${1:?usage: publish-packages.sh <dir of built packages>}" && pwd)"
REMOTE="${ARCH_REPO_REMOTE:?ARCH_REPO_REMOTE is not set}"
REPO="$DISTRO_REPO_NAME"
KEY="${LINUX_GPG_KEY_ID:-$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')}"
[[ -n $KEY ]] || { echo "::error::No signing key: set LINUX_GPG_KEY_ID or import the secret key first."; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"

sign() { gpg --batch --yes -u "$KEY" --passphrase "${LINUX_GPG_PASSPHRASE:-}" --detach-sign --output "$1.sig" "$1"; }

# A package file's name without version, release and architecture.
pkgname_of() { printf '%s' "$1" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//'; }

# The files of package $1 in the current directory. The [0-9] guard keeps
# magnetar-repos-* from matching another package's files.
files_of() {
  find . -maxdepth 1 -type f -printf '%f\n' \
    | grep -E "^$1-[0-9][^-]*-[0-9]+-(any|x86_64|aarch64)\.pkg\.tar\.zst$" || true
}

# Every file a package installs, with its content hash. Metadata (.PKGINFO's
# build date, .MTREE, .BUILDINFO) differs on every build.
payload() {
  local d; d="$(mktemp -d)"
  bsdtar -xf "$1" -C "$d" --exclude '.PKGINFO' --exclude '.MTREE' --exclude '.BUILDINFO'
  ( cd "$d" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum )
  rm -rf "$d"
}

# The database in the current directory as the files Pages serves — real
# files, not repo-add's symlinks — each signed.
finish_db() {
  # repo-add and repo-remove keep the previous database as *.old and rename
  # its signature to *.old.sig; neither belongs in the published tree.
  rm -f "$REPO.db" "$REPO.files" ./*.old ./*.old.sig
  cp "$REPO.db.tar.gz" "$REPO.db"
  cp "$REPO.files.tar.gz" "$REPO.files"
  local db
  for db in "$REPO.db" "$REPO.db.tar.gz" "$REPO.files" "$REPO.files.tar.gz"; do sign "$db"; done
}

# Distro packages are x86_64 or `any`; the distribution is x86_64 only, so
# they go in x86_64/ alone.
stage() {
  local pkg f name old dir p sig n site_bytes superseded gone
  rm -rf "$STAGE"
  git clone -q --depth 1 "$REMOTE" "$STAGE"
  cd "$STAGE/x86_64"
  ADDED=(); REMOVED=(); CHANGED=()
  for pkg in "$DIST"/*.pkg.tar.zst; do
    [[ -e $pkg ]] || continue
    f="$(basename "$pkg")"
    if [ -e "$f" ]; then
      # Already published. For the configuration packages (`any`, nothing
      # compiled, so a rebuild is byte-for-byte the same payload) a difference
      # means the PKGBUILD's files changed without a pkgrel bump, and this run
      # would silently ship nothing. cutecosmic compiles and is not
      # reproducible.
      case "$f" in
        *-any.pkg.tar.zst)
          if [ "$(payload "$pkg")" != "$(payload "$f")" ]; then
            echo "::error::$f is already published with different contents. Bump pkgrel in pkgbuilds/$(pkgname_of "$f")/PKGBUILD to ship the change."
            exit 1
          fi ;;
      esac
      continue
    fi
    cp "$pkg" .
    sign "$f"
    ADDED+=("$f")
    # Keep one superseded version for rollback, as the app pipelines do: a
    # GitHub Pages site may not exceed 1 GB.
    name="$(pkgname_of "$f")"
    # (`|| true`: grep exits 1 when this is the package's only version.)
    files_of "$name" | grep -vx "$f" | sort -V | head -n -1 | while read -r old; do
      echo "Pruning superseded $old"; rm -f "$old" "$old.sig"
    done || true
  done
  cd "$STAGE"

  if [ "${#ADDED[@]}" -gt 0 ]; then
    # [magnetar] is SigLevel = Required: an unsigned package in it is one
    # nobody can install, and a signature without its file verifies nothing.
    # Both architectures, since the app pipelines write aarch64/ too.
    for dir in x86_64 aarch64; do
      [ -d "$dir" ] || continue
      find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.zst' | while read -r p; do
        [ -e "$p.sig" ] || { echo "Removing unsigned $p"; rm -f "$p"; }
      done
      find "$dir" -maxdepth 1 -type f -name '*.sig' | while read -r sig; do
        [ -e "${sig%.sig}" ] || { echo "Removing orphan signature $sig"; rm -f "$sig"; }
      done
    done

    # repo-add appends to the EXISTING database, so the apps' entries survive.
    ( cd x86_64
      rm -f "$REPO.db" "$REPO.files"
      repo-add -q "$REPO.db.tar.gz" "${ADDED[@]}" )
    CHANGED+=(x86_64)
  fi

  # Finish renames: drop every package that another one in the database
  # replaces, with its files. After the additions, so a rename published by
  # this very run is finished by it too.
  for dir in x86_64 aarch64; do
    [ -f "$dir/$REPO.db.tar.gz" ] || continue
    superseded="$("$root/tools/repo-superseded.sh" "$dir/$REPO.db.tar.gz")"
    [ -n "$superseded" ] || continue
    mapfile -t gone <<< "$superseded"
    ( cd "$dir"
      rm -f "$REPO.db" "$REPO.files"
      repo-remove -q "$REPO.db.tar.gz" "${gone[@]}"
      for n in "${gone[@]}"; do
        files_of "$n" | while read -r old; do
          echo "Removing $dir/$old: $n is replaced by another package in [$REPO]"; rm -f "$old" "$old.sig"
        done
      done )
    for n in "${gone[@]}"; do REMOVED+=("$n"); done
    [[ " ${CHANGED[*]} " == *" $dir "* ]] || CHANGED+=("$dir")
  done

  for dir in "${CHANGED[@]}"; do ( cd "$dir" && finish_db ); done
  [ "${#CHANGED[@]}" -gt 0 ] || return 0

  # GitHub Pages will not deploy a site over 1 GB, and says so only after the
  # push has succeeded — this job would go green while repo.magnetaros.com
  # kept serving the last database that fit.
  site_bytes="$(du -sb --exclude=.git . | cut -f1)"
  if [ "$site_bytes" -gt $((950 * 1024 * 1024)) ]; then
    echo "::error::The staged arch-repo tree is $((site_bytes / 1024 / 1024)) MiB; GitHub Pages will not deploy a site over 1 GB."
    exit 1
  fi
}

# What a user's machine does: trust only the published key, require
# signatures on packages and database, sync every database this run changed,
# and fetch every package just added.
validate() {
  local v dir f names=()
  v="$(mktemp -d -p "$WORK")"
  mkdir -p "$v/gnupg"
  pacman-key --gpgdir "$v/gnupg" --init >/dev/null
  pacman-key --gpgdir "$v/gnupg" --add "$STAGE/$REPO.asc" >/dev/null
  pacman-key --gpgdir "$v/gnupg" --lsign-key "$KEY" >/dev/null
  for dir in "${CHANGED[@]}"; do
    mkdir -p "$v/$dir/db" "$v/$dir/cache"
    printf '[options]\nArchitecture = %s\n[%s]\nSigLevel = Required DatabaseRequired\nServer = file://%s/%s\n' \
      "$dir" "$REPO" "$STAGE" "$dir" > "$v/$dir/pacman.conf"
    pacman --config "$v/$dir/pacman.conf" --dbpath "$v/$dir/db" --cachedir "$v/$dir/cache" \
      --gpgdir "$v/gnupg" --noconfirm -Sy
  done
  [ "${#ADDED[@]}" -gt 0 ] || return 0
  for f in "${ADDED[@]}"; do names+=("$(pkgname_of "$f")"); done
  pacman --config "$v/x86_64/pacman.conf" --dbpath "$v/x86_64/db" --cachedir "$v/x86_64/cache" \
    --gpgdir "$v/gnupg" --noconfirm -Sw --nodeps --nodeps "${names[@]}"
}

message() {
  local parts=() removed
  if [ "${#ADDED[@]}" -gt 0 ]; then
    parts+=("$(printf '%s\n' "${ADDED[@]}" | sed -E 's/-([^-]+-[^-]+)-[^-]+\.pkg\.tar\.zst$/ \1/' | paste -sd, - | sed 's/,/, /g') (x86_64)")
  fi
  if [ "${#REMOVED[@]}" -gt 0 ]; then
    removed="$(printf '%s\n' "${REMOVED[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"
    parts+=("$removed removed: replaced by another package")
  fi
  local IFS=';'; printf '%s' "${parts[*]}" | sed 's/;/; /g'
}

for attempt in 1 2 3; do
  stage
  if [ "${#CHANGED[@]}" -eq 0 ]; then
    echo "Every built version is already in [$REPO], and nothing in it is replaced; nothing to publish."
    exit 0
  fi
  validate
  MSG="$(message)"
  git config user.name 'github-actions[bot]'
  git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
  git add -A
  git commit -q -m "$MSG"
  # A rejection means an app released meanwhile. Re-stage against its database
  # rather than rebasing, which would drop one entry.
  if git push -q origin HEAD:main; then
    echo "Published: $MSG"
    exit 0
  fi
  echo "::warning::Push rejected (concurrent release?) — re-staging, attempt $((attempt + 1))/3"
  cd "$root"
done
echo "::error::Could not push to Magnetar-OS/arch-repo after 3 attempts"
exit 1
