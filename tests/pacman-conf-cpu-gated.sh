#!/usr/bin/env bash
# The canonical pacman.conf must not enable any CPU-optimised CachyOS set by
# itself (a znver4 or v4 package SIGILLs on a CPU without AVX-512), and
# magnetar-pacman-conf must enable exactly the requested set, above [magnetar],
# parsing clean — with and without the drop-in Include.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/pkgbuilds/magnetar-repos"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/pacman.d/magnetar-repos.d"
for m in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
  # shellcheck disable=SC2016 # pacman expands $repo and $arch, not the shell
  echo 'Server = https://example.invalid/$repo/$arch' > "$w/pacman.d/$m"
done
cp "$R/repos.d/"*.conf "$w/pacman.d/magnetar-repos.d/"
sed "s|^CANONICAL=.*|CANONICAL=$R/pacman.conf|" "$R/magnetar-pacman-conf" > "$w/mpc"

# repo list of a rendered file, with /etc/pacman.d pointed at the temp dir;
# any stderr from pacman-conf is a failure.
repos() {
  sed "s|^Include = /etc/pacman.d/|Include = $w/pacman.d/|" > "$w/pacman.conf"
  local out
  out=$(pacman-conf --config "$w/pacman.conf" --repo-list 2>"$w/err") || { cat "$w/err"; return 1; }
  [[ ! -s $w/err ]] || { echo "pacman-conf warned: $(cat "$w/err")"; return 1; }
  paste -sd' ' <<<"$out"
}

fail=0
got=$(repos < "$R/pacman.conf") || true
[[ $got == "magnetar cachyos core extra multilib" ]] \
  || { echo "FAIL: canonical file enables more than the CPU-neutral set: $got"; fail=1; }

for level in znver4 v4 v3; do
  want="cachyos-$level cachyos-core-$level cachyos-extra-$level magnetar cachyos core extra multilib"
  got=$(MAGNETAR_CPU_LEVEL=$level bash "$w/mpc" | repos) || true
  [[ $got == "$want" ]] || { echo "FAIL: $level: $got"; fail=1; }
done
got=$(MAGNETAR_CPU_LEVEL=none bash "$w/mpc" | repos) || true
[[ $got == "magnetar cachyos core extra multilib" ]] || { echo "FAIL: none: $got"; fail=1; }

# The installer's first write: no drop-in directory yet on the new root.
rm -rf "$w/pacman.d/magnetar-repos.d"
got=$(MAGNETAR_CPU_LEVEL=v3 bash "$w/mpc" --no-drop-ins | repos) \
  || { echo "FAIL: --no-drop-ins does not parse without the drop-in directory"; fail=1; }

# Writing to a file.
MAGNETAR_CPU_LEVEL=v4 bash "$w/mpc" "$w/written" 2>/dev/null || true
grep -qsx '\[cachyos-v4\]' "$w/written" || { echo "FAIL: FILE argument did not write the v4 set"; fail=1; }

(( fail == 0 )) && echo PASS
exit "$fail"
