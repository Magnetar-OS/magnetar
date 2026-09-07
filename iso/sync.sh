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
  git -C "$work" checkout -q FETCH_HEAD
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

echo "==> patching upstream"
python3 - "$work" "$DISTRO_ID" "$DISTRO_NAME" "$DISTRO_LABEL" "$DISTRO_REPO_URL" <<'PY'
import sys, pathlib

work, did, dname, dlabel, drepo = sys.argv[1:6]
work = pathlib.Path(work)
failed = []

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
      f'iso_publisher="{dname} <https://github.com/entro314-labs/{did}>"',
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
  ( cd "$localrepo" && repo-add -q -R "$DISTRO_ID.db.tar.zst" ./*.pkg.tar.zst >/dev/null )
  echo "    $(find "$localrepo" -name '*.pkg.tar.zst' | wc -l) packages indexed"

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
