#!/usr/bin/env bash
# Renaming the OS must not cut limine's tools off from their boot entries.
#
# limine-entry-tool (kernel entries) and limine-snapper-sync (snapshot entries)
# keep their entries in one top-level group of limine.conf and find it by, in
# order: a `comment: machine-id=<this machine>` inside the group, else the
# group named TARGET_OS_NAME, else — unset — the group named after os-release's
# PRETTY_NAME. CachyOS's installer writes `/+CachyOS` with the machine-id
# comment above the group, where it does not count, so a CachyOS machine is
# found by name alone — and magnetar-branding changes the name.
#
# `finds` below is that lookup, written from the tools' source
# (TreeNode.findOsNode, ConfigReader.readConfig), so each case asserts on what
# the tools would do, not on how magnetar-branding arranges it:
#  - an existing CachyOS machine keeps its group, and limine.conf is untouched;
#  - an owner's TARGET_OS_NAME, a group the tools find anyway and a machine
#    without limine are left alone;
#  - the installer, which has just written an empty /+CachyOS for a system
#    called Magnetar, gets the group named Magnetar with nothing pinned.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
id=0123456789abcdef0123456789abcdef
other=ffffffffffffffffffffffffffffffff

finds() {  # $1: root -> the name of the group limine's tools would use, or nothing
  python3 - "$1" "$id" <<'PY'
import pathlib, re, sys
root, mid = pathlib.Path(sys.argv[1]), sys.argv[2]

def setting(path, key):
    value = None
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == key:
                value = v.strip().strip('"')
    return value

tops, cur = [], None
for line in (root / "boot/limine.conf").read_text().splitlines():
    t = line.strip()
    if t.startswith("/"):
        if len(t) - len(t.lstrip("/")) == 1:
            name = t[1:]
            cur = [name[1:] if name.startswith("+") else name, None]
            tops.append(cur)
        else:
            cur = None  # from its first sub-entry on, lines belong to the sub-entries
    elif cur is not None and t.startswith("comment:"):
        m = re.search(r"machine-id=([a-f0-9]{32})", t, re.I)
        if m:
            cur[1] = m.group(1)

want = setting(root / "etc/default/limine", "TARGET_OS_NAME") \
    or setting(root / "etc/os-release", "PRETTY_NAME")
by_id = [n for n, m in tops if m == mid]
by_name = [n for n, m in tops if n == want and m in (None, mid)]
print((by_id or by_name or [""])[0])
PY
}

# A root as CachyOS's installer leaves it. $2: "booting" adds kernel entries to
# the group, as the first limine-update does; "fresh" is the file the
# bootloader module has just written.
cachyos_root() {
  local r=$1 state=$2
  mkdir -p "$r/etc/default" "$r/boot"
  printf 'NAME="CachyOS Linux"\nPRETTY_NAME="CachyOS"\nID=cachyos\nBUILD_ID=rolling\nANSI_COLOR="38;2;23;147;209"\nLOGO=cachyos\n' > "$r/etc/os-release"
  echo "$id" > "$r/etc/machine-id"
  printf 'ESP_PATH="%s"\nKERNEL_CMDLINE[default]+="quiet rw root=UUID=00000000-0000-0000-0000-000000000000"\nBOOT_ORDER="*, *lts, *fallback, Snapshots"\n' "$r/boot" > "$r/etc/default/limine"
  printf '### defaults\n#TARGET_OS_NAME="Arch Linux"\n' > "$r/etc/limine-entry-tool.conf"
  printf '#TARGET_OS_NAME="CachyOS"\n' > "$r/etc/limine-snapper-sync.conf"
  {
    printf 'timeout: 5\ndefault_entry: 2\nremember_last_entry: yes\n\n'
    # The two lines CachyOS's bootloader module ends the file with.
    printf 'comment: machine-id=%s\n/+CachyOS\n' "$id"
    if [[ $state == booting ]]; then
      printf '  //linux-cachyos\n  comment: kernel-id=linux-cachyos \n  protocol: linux\n  path: boot():/vmlinuz\n'
      printf '/+Other systems and bootloaders\n//Windows Boot Manager\n\tprotocol: efi_chainload\n'
    fi
  } > "$r/boot/limine.conf"
}

# magnetar-branding, acting on root $1.
branding() {
  local r=$1; shift
  sed -e "s|/etc/|$r/etc/|g" -e "s|/usr/share/|$r/usr/share/|g" \
    "$M/pkgbuilds/magnetar-branding/magnetar-branding" > "$w/branding"
  bash "$w/branding" "$@" > /dev/null
}

# --- an existing CachyOS + limine machine installs magnetar-branding ----------
r="$w/adopt"; cachyos_root "$r" booting
[[ $(finds "$r") == CachyOS ]] || bad "the model does not find CachyOS's own group on a CachyOS machine"
cp "$r/boot/limine.conf" "$w/limine.before"; cp "$r/etc/default/limine" "$w/default.before"
branding "$r" all
grep -qx 'PRETTY_NAME="Magnetar"' "$r/etc/os-release" || bad "os-release was not renamed"
[[ $(finds "$r") == CachyOS ]] \
  || bad "after the rename limine's tools find '$(finds "$r")', not the CachyOS group the machine boots from"
cmp -s "$r/boot/limine.conf" "$w/limine.before" || bad "limine.conf of a running machine was edited"
head -n "$(wc -l < "$w/default.before")" "$r/etc/default/limine" | cmp -s - "$w/default.before" \
  || bad "/etc/default/limine lost its existing settings"

# ...and again, as every later transaction's hook does.
cp "$r/etc/default/limine" "$w/default.once"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.once" || bad "a second run changed /etc/default/limine again"

# --- the owner already chose a group -------------------------------------------
r="$w/chosen"; cachyos_root "$r" booting
echo 'TARGET_OS_NAME="Mine"' >> "$r/etc/default/limine"
cp "$r/etc/default/limine" "$w/default.before"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "an existing TARGET_OS_NAME was overridden"

# --- a group the tools find whatever the OS is called ---------------------------
r="$w/by-id"; cachyos_root "$r" booting
sed -i "s|^/+CachyOS$|/+CachyOS\n  comment: machine-id=$id order-priority=50|" "$r/boot/limine.conf"
cp "$r/etc/default/limine" "$w/default.before"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "pinned although the group carries this machine's id"
[[ $(finds "$r") == CachyOS ]] || bad "by-id: tools find '$(finds "$r")'"

# A machine renamed by an earlier magnetar-branding, where limine-entry-tool
# has since started its own group: the tools use that one; do not move them back.
r="$w/generated"; cachyos_root "$r" booting
printf '/+Magnetar\n  comment: Magnetar\n  comment: machine-id=%s order-priority=50\n  //linux-cachyos\n  protocol: linux\n' "$id" >> "$r/boot/limine.conf"
cp "$r/etc/default/limine" "$w/default.before"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "pinned although the tools already have a Magnetar group"
[[ $(finds "$r") == Magnetar ]] || bad "generated: tools find '$(finds "$r")'"

# A /+CachyOS that belongs to another installation on the same ESP.
r="$w/foreign"; cachyos_root "$r" booting
sed -i "s|^/+CachyOS$|/+CachyOS\n  comment: machine-id=$other|" "$r/boot/limine.conf"
cp "$r/etc/default/limine" "$w/default.before"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "pinned to a group that carries another machine's id"

# --- no limine ------------------------------------------------------------------
r="$w/grub"; cachyos_root "$r" booting
rm "$r/boot/limine.conf" "$r/etc/default/limine" "$r/etc/limine-entry-tool.conf" "$r/etc/limine-snapper-sync.conf"
branding "$r" all
[[ ! -e $r/etc/default/limine ]] || bad "created /etc/default/limine on a machine without limine"
branding "$r" name-boot-group || bad "name-boot-group fails on a machine without limine"

# --- the installer: a fresh limine.conf for a system already called Magnetar ---
# In the order the installer does it: the packages first (magnetar-branding's
# post_install renames the OS while there is no bootloader configuration yet),
# then CachyOS's bootloader module writes limine.conf and /etc/default/limine.
r="$w/install"; cachyos_root "$r" fresh
mv "$r/boot/limine.conf" "$r/etc/default/limine" "$w/"
branding "$r" all
[[ ! -e $r/etc/default/limine ]] || bad "post_install created /etc/default/limine before the bootloader step"
mv "$w/limine.conf" "$r/boot/limine.conf"; mv "$w/limine" "$r/etc/default/limine"
cp "$r/boot/limine.conf" "$w/limine.before"; cp "$r/etc/default/limine" "$w/default.before"
[[ -z $(finds "$r") ]] || bad "the model finds a group in a fresh CachyOS limine.conf on a system called Magnetar"
branding "$r" name-boot-group
[[ $(finds "$r") == Magnetar ]] || bad "after name-boot-group the tools find '$(finds "$r")', not Magnetar"
diff <(sed 's|^/+CachyOS$|/+Magnetar|' "$w/limine.before") "$r/boot/limine.conf" > /dev/null \
  || bad "name-boot-group changed more than the group's name"
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "the installer path pinned TARGET_OS_NAME"
branding "$r" all
cmp -s "$r/etc/default/limine" "$w/default.before" || bad "a later hook pinned TARGET_OS_NAME on a fresh install"

(( fail == 0 )) && echo PASS
exit "$fail"
