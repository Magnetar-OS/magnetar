#!/usr/bin/env bash
# The Calamares configuration magnetar-install assembles from CachyOS's must
#  - load Magnetar's netinstall.yaml and nothing else (audit F-01), and
#  - give the target a pacman.conf with this CPU's optimised set, then
#    [magnetar], then [cachyos] — first without the drop-in Include (pacstrap
#    on an empty root), then, from inside the target, the full canonical file
#    (audit F-02);
#  - install what the steps Magnetar keeps from CachyOS act on: it enables
#    bluetooth.service and configures ufw, so the list must carry both;
#  - name limine's boot-entry group after the installed system before the
#    first limine-update: CachyOS's bootloader module writes `/+CachyOS`, which
#    limine's tools cannot find on a system called Magnetar.
#
# Runs against the real cachyos-calamares-next package: pass the directory it
# is extracted in, or have [cachyos] configured on this host and the script
# downloads the current one.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
CAL="$M/pkgbuilds/magnetar-calamares"
REPOS="$M/pkgbuilds/magnetar-repos"
ASSEMBLE="${ASSEMBLE:-python3 $CAL/assemble-config.py}"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT

src=${1:-}
if [[ -z $src ]]; then
  url=$(pacman -Sp cachyos-calamares-next | tail -n1)
  curl -fsSL -o "$w/cal.pkg.tar.zst" "$url"
  mkdir "$w/cal"; bsdtar -xf "$w/cal.pkg.tar.zst" -C "$w/cal" etc/calamares usr/share/calamares/settings_online.conf \
    usr/lib/calamares/modules/bootloader/main.py
  src="$w/cal"
fi

# What magnetar-install does, into a temp CONFDIR.
conf="$w/confdir"
mkdir -p "$conf"
cp -a "$src/etc/calamares/." "$conf/"
cp "$src/usr/share/calamares/settings_online.conf" "$conf/settings.conf"
cp -a "$CAL/modules/." "$conf/modules/"
$ASSEMBLE "$conf" >/dev/null

fail=0
bad() { echo "FAIL: $*"; fail=1; }

grep -q '^branding: magnetar' "$conf/settings.conf" || bad "settings.conf branding is not magnetar"
! grep -q 'packagechooser@desktop' "$conf/settings.conf" || bad "the desktop chooser is still in the sequence"

# F-01: the only groups source is Magnetar's list.
urls=$(awk '/^groupsUrl:/ { sub(/^groupsUrl:[ \t]*/, ""); if ($0 != "") print; list = 1; next }
            list && /^[ \t]+- / { sub(/^[ \t]+- /, ""); print; next }
            { list = 0 }' "$conf/modules/netinstall.conf")
[[ $urls == "file://$conf/modules/netinstall.yaml" ]] || bad "netinstall groupsUrl is: $(paste -sd' ' <<<"$urls")"
cmp -s "$conf/modules/netinstall.yaml" "$CAL/modules/netinstall.yaml" || bad "netinstall.yaml is not Magnetar's"

# F-02: run the shellprocess commands against a fake target root, with the
# repo's magnetar-pacman-conf standing in for the installed one.
sed "s|^CANONICAL=.*|CANONICAL=$REPOS/pacman.conf|" "$REPOS/magnetar-pacman-conf" > "$w/mpc"
commands() {  # the command: strings of one shellprocess config, in order
  sed -nE 's/^[ \t]*- command: "(.*)"$/\1/p' "$conf/modules/$1"
}
root="$w/root"; mkdir -p "$root/etc/pacman.d"
for m in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
  # shellcheck disable=SC2016 # pacman expands $repo and $arch
  echo 'Server = https://example.invalid/$repo/$arch' > "$root/etc/pacman.d/$m"
done
run_in() {  # $1: "host" (dontChroot) or "target"
  local where=$1 c; shift
  while read -r c; do
    [[ $c == */magnetar-pacman-conf* ]] || continue
    # shellcheck disable=SC2016 # the literal ${ROOT} Calamares substitutes
    c=${c//'${ROOT}'/$root}
    [[ $where == target ]] && c=${c//' /etc/'/" $root/etc/"}
    c=${c//\/usr\/bin\/magnetar-pacman-conf/bash $w/mpc}
    MAGNETAR_CPU_LEVEL=v3 eval "$c" 2>/dev/null
  done
}
repos() {
  sed "s|^Include = /etc/pacman.d/|Include = $root/etc/pacman.d/|" "$root/etc/pacman.conf" > "$w/check.conf"
  local out
  out=$(pacman-conf --config "$w/check.conf" --repo-list 2>"$w/err") || { echo "parse error: $(cat "$w/err")"; return 0; }
  [[ -s $w/err ]] && { echo "warning: $(cat "$w/err")"; return 0; }
  paste -sd' ' <<<"$out"
}
want="cachyos-v3 cachyos-core-v3 cachyos-extra-v3 magnetar cachyos core extra multilib"

! grep -q 'pacman-more.conf' "$conf/modules/shellprocess-before-online.conf" \
  || bad "before-online still copies pacman-more.conf"
commands shellprocess-before-online.conf | run_in host
[[ -f $root/etc/pacman.conf ]] || bad "before-online wrote no pacman.conf into the target"
got=$(repos); [[ $got == "$want" ]] || bad "target pacman.conf for pacstrap: $got"
! grep -q '^Include = /etc/pacman.d/magnetar-repos.d/' "$root/etc/pacman.conf" \
  || bad "the pacstrap pacman.conf includes drop-ins that do not exist yet"

# After packages@online, magnetar-repos (and its drop-ins) are in the target.
mkdir -p "$root/etc/pacman.d/magnetar-repos.d"
cp "$REPOS/repos.d/"*.conf "$root/etc/pacman.d/magnetar-repos.d/"
commands shellprocess.conf | run_in target
got=$(repos); [[ $got == "$want" ]] || bad "installed pacman.conf: $got"
MAGNETAR_CPU_LEVEL=v3 bash "$w/mpc" | cmp -s - "$root/etc/pacman.conf" \
  || bad "installed pacman.conf is not the canonical file rendered for this CPU"

# The steps kept from CachyOS need their packages. services-systemd enables
# bluetooth.service, and enable-ufw turns the firewall on when ufw is there.
listed() { grep -qE "^[[:space:]]+- $1[[:space:]]*\$" "$conf/modules/netinstall.yaml"; }
grep -qE '^[[:space:]]*- name: "?bluetooth"?' "$conf/modules/services-systemd.conf" \
  || bad "CachyOS no longer enables bluetooth.service; re-read services-systemd.conf"
listed bluez || bad "the installer enables bluetooth.service but installs no bluez"
grep -q 'pacman -Qs ufw' "$conf/scripts/enable-ufw" \
  || bad "CachyOS's enable-ufw no longer keys on the ufw package; re-read it"
listed ufw || bad "the installer's firewall step has no ufw to enable"

# limine. CachyOS's bootloader module ends limine.conf with these two lines:
# the machine-id comment outside the group, and the group named CachyOS.
# magnetar-branding's name-boot-group is written against exactly that.
boot="$src/usr/lib/calamares/modules/bootloader/main.py"
# shellcheck disable=SC2016 # the literal Python source
{ grep -qF 'config_file.write(f"comment: machine-id={machine_id}\n")' "$boot" \
    && grep -qF 'config_file.write(f"/+CachyOS\n")' "$boot"; } \
  || bad "CachyOS's bootloader module no longer writes '/+CachyOS' the way magnetar-branding expects"
order=$(grep -nE 'magnetar-branding name-boot-group|scripts/bootloader-post-setup"' "$conf/modules/shellprocess.conf" \
        | grep -v -- '-rm ' | sed -E 's/^[0-9]+:.*(name-boot-group|bootloader-post-setup).*/\1/' | paste -sd' ')
[[ $order == "name-boot-group bootloader-post-setup" ]] \
  || bad "shellprocess.conf does not name the limine group before bootloader-post-setup's limine-update: '$order'"

# Running it again must change nothing (magnetar-install re-assembles on every launch).
cp -a "$conf" "$w/first"
$ASSEMBLE "$conf" >/dev/null || bad "a second assembly fails"
diff -r "$w/first" "$conf" >/dev/null || bad "a second assembly changes the result"

(( fail == 0 )) && echo PASS
exit "$fail"
