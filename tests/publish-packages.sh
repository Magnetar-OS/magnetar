#!/usr/bin/env bash
# tools/publish-packages.sh — the Packages workflow's publish step — run whole
# against a throwaway arch-repo and signing key.
#
# The repository starts as the real one looks after an app was renamed: the
# editor's pipeline has published magnetar-pencil, which replaces
# `pencil<=1.2.0`, in both architectures, and the old `pencil` is still in the
# databases with its files. One run must then
#  - add a new distribution package version, signed, and prune to the newest
#    plus one superseded version;
#  - finish the rename: `pencil` leaves both databases and both directories,
#    while a package whose version a `replaces` bound does not cover stays;
#  - leave every file signed, the databases signed and equal to their
#    .tar.gz, and nothing else behind;
# and a second run must publish nothing, and a rebuilt package with changed
# contents under an already-published version must stop the run.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GNUPGHOME="$w/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-generate-key 'Throwaway repository key <test@example.invalid>' ed25519 sign never 2>/dev/null
KEY="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
sign() { gpg --batch --yes --quiet -u "$KEY" --detach-sign --output "$1.sig" "$1"; }

mkpkg() {  # dest dir, name, version-release, arch, payload text, [replaces]
  local dest=$1 name=$2 ver=${3%-*} rel=${3##*-} arch=$4 text=$5 replaces=${6:-}
  local b="$w/b/$name-$3-$arch"
  mkdir -p "$b" "$dest"
  {
    echo "pkgname=$name"; echo "pkgver=$ver"; echo "pkgrel=$rel"; echo "arch=($arch)"
    [[ -z $replaces ]] || echo "replaces=('$replaces')"
    echo "package() { install -Dm644 /dev/stdin \"\$pkgdir/usr/share/$name/file\" <<< '$text'; }"
  } > "$b/PKGBUILD"
  (cd "$b" && CARCH="${arch/any/x86_64}" PKGDEST="$dest" BUILDDIR="$b" makepkg -f --nodeps >/dev/null 2>&1) \
    || { echo "could not build $name $3 ($arch)" >&2; exit 2; }
}

# What a publisher does to one architecture directory: sign every package,
# build the database from the newest of each name, real files, signed.
publish_seed() {  # dir, newest package files...
  local dir=$1 p db; shift
  ( cd "$dir"
    for p in ./*.pkg.tar.zst; do sign "$p"; done
    repo-add -q magnetar.db.tar.gz "$@"
    rm -f magnetar.db magnetar.files
    cp magnetar.db.tar.gz magnetar.db; cp magnetar.files.tar.gz magnetar.files
    for db in magnetar.db magnetar.db.tar.gz magnetar.files magnetar.files.tar.gz; do sign "$db"; done )
}

seed="$w/seed"
mkdir -p "$seed"
gpg --armor --export "$KEY" > "$seed/magnetar.asc"
for arch in x86_64 aarch64; do
  mkpkg "$seed/$arch" circle 1.0.0-1 "$arch" circle
  mkpkg "$seed/$arch" pencil 1.2.0-1 "$arch" pencil
  mkpkg "$seed/$arch" magnetar-pencil 1.3.0-1 "$arch" pencil 'pencil<=1.2.0'
done
mkpkg "$seed/x86_64" pencil 1.1.0-1 x86_64 pencil
mkpkg "$seed/x86_64" magnetar-repos 0.1.0-5 any five
mkpkg "$seed/x86_64" magnetar-repos 0.1.0-6 any six
# A bound that does not cover the published version: `other` must stay.
mkpkg "$seed/x86_64" other 3.0.0-1 x86_64 other
mkpkg "$seed/x86_64" magnetar-other 1.0.0-1 x86_64 other 'other<=1.0.0'
publish_seed "$seed/x86_64" circle-1.0.0-1-x86_64.pkg.tar.zst pencil-1.2.0-1-x86_64.pkg.tar.zst \
  magnetar-pencil-1.3.0-1-x86_64.pkg.tar.zst magnetar-repos-0.1.0-6-any.pkg.tar.zst \
  other-3.0.0-1-x86_64.pkg.tar.zst magnetar-other-1.0.0-1-x86_64.pkg.tar.zst
publish_seed "$seed/aarch64" circle-1.0.0-1-aarch64.pkg.tar.zst pencil-1.2.0-1-aarch64.pkg.tar.zst \
  magnetar-pencil-1.3.0-1-aarch64.pkg.tar.zst

git init -q --bare -b main "$w/arch-repo.git"
git -C "$seed" init -q -b main
git -C "$seed" add -A
git -C "$seed" -c user.name=seed -c user.email=seed@example.invalid commit -q -m seed
git -C "$seed" push -q "$w/arch-repo.git" main
head_of() { git -C "$w/arch-repo.git" rev-parse main; }

# fakeroot: the script checks its result with pacman-key and pacman -Sy, which
# want root, as the workflow's container gives them.
publish() { ARCH_REPO_REMOTE="$w/arch-repo.git" fakeroot bash "$M/tools/publish-packages.sh" "$1" > "$w/out" 2>&1; }

# --- one publish ---------------------------------------------------------------
mkpkg "$w/dist" magnetar-repos 0.1.0-7 any seven
mkpkg "$w/dist" magnetar-repos 0.1.0-6 any six          # rebuilt, unchanged: already published
mkpkg "$w/dist" magnetar-settings 0.1.0-1 any settings   # a package's first version
publish "$w/dist" || { echo "FAIL: publish-packages.sh failed:"; cat "$w/out"; exit 1; }

git clone -q "$w/arch-repo.git" "$w/result"
r="$w/result"
has() { [[ -e $r/$1 ]]; }
entries() { bsdtar -tf "$r/$1/magnetar.db" | sed -n 's|/desc$||p' | sort | paste -sd' '; }

has x86_64/magnetar-repos-0.1.0-7-any.pkg.tar.zst || bad "the new version was not added"
has x86_64/magnetar-repos-0.1.0-6-any.pkg.tar.zst || bad "the one superseded version was not kept"
! has x86_64/magnetar-repos-0.1.0-5-any.pkg.tar.zst || bad "the second superseded version was not pruned"
! has x86_64/magnetar-repos-0.1.0-5-any.pkg.tar.zst.sig || bad "a pruned package's signature was left"
has x86_64/magnetar-settings-0.1.0-1-any.pkg.tar.zst || bad "a package's first version was not added"

for arch in x86_64 aarch64; do
  [[ -z $(find "$r/$arch" -name 'pencil-*') ]] || bad "$arch still has the replaced pencil's files"
  has "$arch/magnetar-pencil-1.3.0-1-$arch.pkg.tar.zst" || bad "$arch lost magnetar-pencil"
  has "$arch/circle-1.0.0-1-$arch.pkg.tar.zst" || bad "$arch lost an unrelated package"
done
want="circle-1.0.0-1 magnetar-other-1.0.0-1 magnetar-pencil-1.3.0-1 magnetar-repos-0.1.0-7 magnetar-settings-0.1.0-1 other-3.0.0-1"
[[ $(entries x86_64) == "$want" ]] || bad "x86_64 database: $(entries x86_64)"
[[ $(entries aarch64) == "circle-1.0.0-1 magnetar-pencil-1.3.0-1" ]] || bad "aarch64 database: $(entries aarch64)"
has x86_64/other-3.0.0-1-x86_64.pkg.tar.zst || bad "a package outside the replaces bound was removed"

for arch in x86_64 aarch64; do
  for f in "$r/$arch"/*; do
    case "$f" in
      *.sig) [[ -e ${f%.sig} ]] || bad "orphan signature $(basename "$f")" ;;
      *.old|*.old.*) bad "left behind: $(basename "$f")" ;;
      *) gpg --batch --quiet --verify "$f.sig" "$f" 2>/dev/null || bad "$arch/$(basename "$f") has no valid signature" ;;
    esac
  done
  cmp -s "$r/$arch/magnetar.db" "$r/$arch/magnetar.db.tar.gz" || bad "$arch: magnetar.db is not its .tar.gz"
  cmp -s "$r/$arch/magnetar.files" "$r/$arch/magnetar.files.tar.gz" || bad "$arch: magnetar.files is not its .tar.gz"
  [[ ! -L $r/$arch/magnetar.db ]] || bad "$arch: magnetar.db is a symlink, which Pages does not serve"
done
msg="$(git -C "$r" log -1 --format=%s)"
[[ $msg == *"magnetar-repos 0.1.0-7"* && $msg == *"pencil removed"* ]] || bad "commit message: $msg"

# --- the same packages again: nothing to publish ---------------------------------
before="$(head_of)"
publish "$w/dist" || { bad "a second run failed:"; cat "$w/out"; }
[[ $(head_of) == "$before" ]] || bad "a second run with nothing new pushed a commit"

# --- contents changed under a published version ----------------------------------
mkpkg "$w/dist2" magnetar-repos 0.1.0-7 any 'seven, edited without a pkgrel bump'
if publish "$w/dist2"; then
  bad "a changed package under a published version was accepted"
elif ! grep -q 'already published with different contents' "$w/out"; then
  bad "the changed package was refused for another reason:"; cat "$w/out"
fi
[[ $(head_of) == "$before" ]] || bad "the refused run pushed a commit"

(( fail == 0 )) && echo PASS
exit "$fail"
