#!/usr/bin/env bash
#
# Fetch CachyOS-Live-ISO at the pinned ref, apply the Magnetar overlay, and leave
# a tree that buildiso.sh can run.
#
# Why an overlay instead of a fork: CachyOS actively maintains that repo, and a
# hard fork means silently falling behind its hardware and firmware work. The
# overlay is small enough to review — a package list, three branding files, and
# four assertions against upstream text. When upstream changes any of the text
# we patch, this fails and says which one, instead of producing an ISO that is
# subtly wrong.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

work="${MAGNETAR_ISO_WORK:-$root/build/iso-src}"
overlay="$root/iso/overlay"

echo "==> upstream: $UPSTREAM_ISO_REPO @ $UPSTREAM_ISO_REF"
if [[ -d $work/.git ]]; then
  git -C "$work" fetch --depth 1 origin "$UPSTREAM_ISO_REF"
  # Hard reset, not checkout. The patches below rewrite tracked files, and a
  # plain checkout leaves those edits in place — so when OUR replacement text
  # changes (an org rename, say), the patch matches neither the pristine text
  # nor the already-applied text, and sync fails on a tree it created itself.
  # Resetting to upstream every run makes this idempotent from any state.
  git -C "$work" reset -q --hard FETCH_HEAD
  git -C "$work" clean -qfd
else
  rm -rf "$work"
  mkdir -p "$(dirname "$work")"
  git clone --depth 1 --branch "$UPSTREAM_ISO_REF" "$UPSTREAM_ISO_REPO" "$work"
fi
echo "    at $(git -C "$work" rev-parse --short HEAD)"

echo "==> applying overlay"
cp -a "$overlay/archiso/." "$work/archiso/"

# Upstream's airootfs is a Plasma live session: its /etc/skel seeds Plasma
# configuration and it ships plasmalogin settings. An overlay can only add
# files, so these are deleted explicitly — otherwise magnetar-settings' COSMIC
# skel arrives via pacstrap and Plasma's dotfiles land on top of it.
echo "==> removing Plasma leftovers"
for f in \
  etc/skel/.config/kded5rc \
  etc/skel/.config/kscreenlockerrc \
  etc/skel/.config/kwalletrc \
  etc/skel/.config/plasma-welcomerc \
  etc/skel/.config/powerdevilrc \
  etc/skel/.config/powermanagementprofilesrc \
  etc/skel/.config/systemd/user/plasma-login-kwin_wayland.service.d \
  etc/plasmalogin.conf \
  etc/plasmalogin.conf.d \
  usr/local/bin/calamares-online.sh \
  etc/pacman.d/hooks/90-cachyos-live-kwin-keyboard.hook
do
  if [[ -e $work/archiso/airootfs/$f ]]; then
    rm -rf "$work/archiso/airootfs/$f"
    echo "    removed $f"
  fi
done

# --- rebrand the boot menus and the motd -------------------------------------
# Derived from upstream with a substitution rather than forked. These files
# gain entries as CachyOS adds kernels and boot options, and a hand-maintained
# copy would quietly stop matching what the ISO can actually boot.
#
# Visible strings only. CACHYOS_VERSION inside grub.cfg stays as it is: it is a
# build-internal variable that change_grub_version() seds by name, renaming it
# would mean patching that function too, and nobody ever sees it.
echo "==> rebranding boot menus"
for f in "$work/archiso/grub/grub.cfg" "$work"/archiso/syslinux/*.cfg; do
  [[ -f $f ]] || continue
  before=$(md5sum "$f" | cut -d' ' -f1)
  sed -i \
    -e "s|Welcome to CachyOS|Welcome to $DISTRO_NAME|g" \
    -e "s|menuentry \"CachyOS\"|menuentry \"$DISTRO_NAME\"|g" \
    -e "s|menuentry \"CachyOS |menuentry \"$DISTRO_NAME |g" \
    -e "s|MENU TITLE CachyOS|MENU TITLE $DISTRO_NAME|g" \
    -e "s|CachyOS install medium|$DISTRO_NAME install medium|g" \
    -e "s|CachyOS live medium|$DISTRO_NAME live medium|g" \
    -e "s|install CachyOS|install $DISTRO_NAME|g" \
    -e "s|the CachyOS|the $DISTRO_NAME|g" \
    -e "s|https://cachyos.org|$DISTRO_URL|g" \
    "$f"
  after=$(md5sum "$f" | cut -d' ' -f1)
  [[ $before != "$after" ]] && echo "    rebranded ${f#"$work"/}"
done

echo "==> patching upstream"
python3 - "$work" "$DISTRO_ID" "$DISTRO_NAME" "$DISTRO_LABEL" "$DISTRO_REPO_URL" <<'PY'
import sys, pathlib

work, did, dname, dlabel, drepo = sys.argv[1:6]
work = pathlib.Path(work)
failed = []

def remove(relpath, text, why):
    """Delete exact text. Absence is what 'already applied' means here, so this
    cannot share patch()'s marker logic — a removal has no replacement to look
    for."""
    p = work / relpath
    s = p.read_text()
    if text not in s:
        print(f"    ok (already) {relpath}: {why}")
        return
    p.write_text(s.replace(text, "", 1))
    print(f"    patched {relpath}: {why}")


def patch(relpath, old, new, why, marker=None):
    """Replace exact text, or record a failure naming what moved.

    `marker` is text that exists only once the patch is applied. It defaults to
    the replacement, which is right when the patch rewrites text. When the
    patch *inserts* — so the original is a substring of the replacement — the
    caller must pass a marker, or a second run appends the insertion again.
    """
    p = work / relpath
    s = p.read_text()
    if (marker or new) in s:
        print(f"    ok (already) {relpath}: {why}")
        return
    if old not in s:
        failed.append(f"{relpath}: expected text for '{why}' is gone upstream")
        return
    p.write_text(s.replace(old, new, 1))
    print(f"    patched {relpath}: {why}")

# --- profiledef.sh: branding ------------------------------------------------
patch("archiso/profiledef.sh",
      'iso_name="cachyos"',
      f'iso_name="{did}"',
      "iso_name")
patch("archiso/profiledef.sh",
      'iso_label="COS_$(date',
      f'iso_label="{dlabel}_$(date',
      "iso_label")
patch("archiso/profiledef.sh",
      'iso_publisher="CachyOS <https://cachyos.org>"',
      f'iso_publisher="{dname} <https://github.com/Magnetar-OS/{did}>"',
      "iso_publisher")
patch("archiso/profiledef.sh",
      'iso_application="CachyOS Live/Rescue DVD"',
      f'iso_application="{dname} Live"',
      "iso_application")

# --- util-iso.sh: teach it the magnetar profile -------------------------------
# Upstream hardcodes a single 'desktop' profile and dies on anything else.
# Three functions test for it; each gets the new profile alongside, never
# instead — the desktop profile keeps working, which is what makes a bad patch
# obvious rather than silent.
patch("util-iso.sh",
      '    if [ "$_profile" == "desktop" ]; then\n'
      "        cat << 'EOF' > ${src_dir}/archiso/airootfs/etc/environment",
      f'    if [ "$_profile" == "desktop" ] || [ "$_profile" == "{did}" ]; then\n'
      "        cat << 'EOF' > ${src_dir}/archiso/airootfs/etc/environment",
      "generate_environment accepts the magnetar profile")

patch("util-iso.sh",
      '    if [ "$_profile" == "desktop" ]; then\n'
      '        echo "${_version}" > ${src_dir}/archiso/airootfs/etc/version-tag',
      f'    if [ "$_profile" == "desktop" ] || [ "$_profile" == "{did}" ]; then\n'
      '        echo "${_version}" > ${src_dir}/archiso/airootfs/etc/version-tag',
      "generate_version_tag accepts the magnetar profile")

# The display manager: Plasma's greeter for the upstream profile, COSMIC's for
# ours. This is the one line that decides which desktop the live session boots.
patch("util-iso.sh",
      '    if [ "$profile" == "desktop" ]; then\n'
      '        cp ${src_dir}/archiso/packages_desktop.x86_64 ${src_dir}/archiso/packages.x86_64\n'
      '        ln -sf /usr/lib/systemd/system/plasmalogin.service ${src_dir}/archiso/airootfs/etc/systemd/system/display-manager.service\n'
      '    else',
      '    if [ "$profile" == "desktop" ]; then\n'
      '        cp ${src_dir}/archiso/packages_desktop.x86_64 ${src_dir}/archiso/packages.x86_64\n'
      '        ln -sf /usr/lib/systemd/system/plasmalogin.service ${src_dir}/archiso/airootfs/etc/systemd/system/display-manager.service\n'
      f'    elif [ "$profile" == "{did}" ]; then\n'
      f'        cp ${{src_dir}}/archiso/packages_{did}.x86_64 ${{src_dir}}/archiso/packages.x86_64\n'
      '        # cosmic-greeter.service is the unit, not greetd.service: it runs\n'
      '        # `greetd --config /etc/greetd/cosmic-greeter.toml` and declares\n'
      '        # Alias=display-manager.service. Pointing at greetd.service\n'
      '        # instead boots the plain agreety text greeter.\n'
      '        ln -sf /usr/lib/systemd/system/cosmic-greeter.service ${src_dir}/archiso/airootfs/etc/systemd/system/display-manager.service\n'
      '    else',
      "prepare_profile builds the magnetar profile")

# --- util-iso.sh: two more hardcoded "cachyos" strings -----------------------
# The build otherwise succeeds and then fails on its last line. mkarchiso names
# the image from profiledef's iso_name, which is now "magnetar", but upstream's
# rename step still looks for "cachyos-<date>-x86_64.iso" and dies. The ISO is
# fine at that point; the checksum step after it never runs.
patch("util-iso.sh",
      '    mv "$outFolder/$_profile/cachyos-$(date',
      '    mv "$outFolder/$_profile/${iso_name}-$(date',
      "the final rename uses iso_name, not a literal")

# gen_iso_fn builds the published filename. Left alone it produces
# "cachyos-magnetar-linux-260908.iso", which names the wrong distribution first.
patch("util-iso.sh",
      '    vars+=("cachyos")\n',
      f'    vars+=("{did}")\n',
      "generated filenames start with the distribution's own name")

# --- motd --------------------------------------------------------------------
# prepare_profile() calls generate_motd(), which writes a CachyOS welcome over
# whatever the overlay put there — the overlay is copied first, so ours loses.
# Disable the call and let our file stand.
patch("util-iso.sh",
      "    generate_motd\n",
      "    # generate_motd — disabled; Magnetar ships its own /etc/motd in the\n"
      "    # overlay, and this would overwrite it.\n",
      "generate_motd does not overwrite our motd",
      marker="# generate_motd — disabled")

# --- profiledef.sh: drop permissions for a file we deleted -------------------
# mkarchiso warns for every file_permissions entry whose file is missing.
# calamares-online.sh is removed above — magnetar-install replaces it — so the
# entry is now noise in every build log.
remove("archiso/profiledef.sh",
       '  ["/usr/local/bin/calamares-online.sh"]="0:0:755"\n',
       "permissions entry for the removed calamares-online.sh")

# --- archiso/pacman.conf: the repo the ISO installs Magnetar packages from -----
patch("archiso/pacman.conf",
      "[cachyos]\nServer = https://mirror.cachyos.org/repo/$arch/$repo",
      "[cachyos]\nServer = https://mirror.cachyos.org/repo/$arch/$repo\n"
      "\n"
      "# Magnetar packages. Below [cachyos] and above [core], matching the order\n"
      "# the installed system gets — see docs/REPOS.md. Signed: the build must\n"
      "# fail on a bad signature rather than bake an unverified package into an\n"
      "# ISO that other people boot.\n"
      f"[{did}]\n"
      "SigLevel = Required DatabaseOptional\n"
      f"Server = {drepo}/$arch",
      "magnetar repository available at build time",
      marker=f"[{did}]")

if failed:
    print("\n!! upstream has moved under this overlay:", file=sys.stderr)
    for f in failed:
        print(f"     {f}", file=sys.stderr)
    print("\n   Re-read the upstream file, update iso/sync.sh, and bump\n"
          "   UPSTREAM_ISO_REF in branding.env in the same commit.", file=sys.stderr)
    sys.exit(1)
PY

# --- local package repository -----------------------------------------------
# The published [magnetar] repository does not exist yet, and even once it does,
# testing an ISO means testing packages that have not been published. When
# build/repo holds packages, point the ISO's [magnetar] at them over file://.
localrepo="$root/build/repo/x86_64"
if compgen -G "$localrepo/*.pkg.tar.zst" > /dev/null; then
  echo "==> using local package repository"
  # Regenerate the database, then delete its signatures.
  #
  # This repo-add is unsigned — signing is tools/sign-packages.sh's job, and it
  # needs a passphrase this script has no business asking for. But a database
  # rebuilt here no longer matches a signature left over from a signed run, and
  # pacman rejects a mismatched database signature outright ("signature ... is
  # invalid"), which is NOT waived by SigLevel = Optional TrustAll: TrustAll
  # forgives an unknown key, not a signature that does not verify.
  #
  # The individual package signatures are left alone; they are still valid.
  ( cd "$localrepo"
    repo-add -q -R "$DISTRO_ID.db.tar.zst" ./*.pkg.tar.zst >/dev/null
    rm -f "$DISTRO_ID.db.sig" "$DISTRO_ID.db.tar.zst.sig" \
          "$DISTRO_ID.files.sig" "$DISTRO_ID.files.tar.zst.sig"
  )
  echo "    $(find "$localrepo" -name '*.pkg.tar.zst' | wc -l) packages indexed (database unsigned for the test build)"

  python3 "$root/tools/point-iso-at-local-repo.py" \
    "$work/archiso/pacman.conf" "$DISTRO_ID" "$localrepo"
  echo "    [$DISTRO_ID] -> file://$localrepo (unsigned, test build only)"
else
  echo "==> no local packages in $localrepo"
  echo "    [$DISTRO_ID] still points at $DISTRO_REPO_URL, which is not published."
  echo "    Build packages first, or the ISO build cannot resolve magnetar-*."
fi

echo
echo "==> ready: $work"
echo "    build with:  cd $work && sudo ./buildiso.sh -p $DISTRO_ID -v -w"
echo "    output:      $work/out/$DISTRO_ID/"
