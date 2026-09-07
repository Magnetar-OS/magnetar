#!/usr/bin/env bash
#
# magnetar-repo-audit — prove the repository order and locks still hold.
#
# Repository order in pacman.conf is a hard priority: pacman takes each package
# from the first configured repository that carries the name and never looks
# lower. That makes shadowing invisible in normal use — the machine keeps
# working, it is just being sourced from somewhere nobody chose. This checks it
# on purpose.
#
# Exit codes: 0 clean, 1 policy violation, 2 could not run.
set -euo pipefail

SELF="${0##*/}"
OVERRIDES="${MAGNETAR_REPO_OVERRIDES:-/usr/share/magnetar/repo-overrides.txt}"
fail=0
warn=0

command -v pacman-conf >/dev/null || { echo "$SELF: pacman-conf not found" >&2; exit 2; }

# Repositories in configured order. This ordering is the entire point; do not
# sort it.
mapfile -t repos < <(pacman-conf --repo-list)
[[ ${#repos[@]} -gt 0 ]] || { echo "$SELF: no repositories configured" >&2; exit 2; }

# Position of each repo, and where Arch's own repos sit.
declare -A pos
for i in "${!repos[@]}"; do pos[${repos[$i]}]=$i; done

# The three stable Arch repositories. Their position is what "above Arch"
# means, and it is measured per package: a name's natural home is the first of
# these that carries it, because that is where pacman would take it from if
# nothing above interfered.
_is_arch_repo() { case "$1" in core|extra|multilib) return 0;; *) return 1;; esac; }

have_arch=0
for r in core extra multilib; do [[ -n ${pos[$r]:-} ]] && have_arch=1; done
if (( ! have_arch )); then
  echo "$SELF: none of core/extra/multilib are configured — refusing to guess" >&2
  exit 2
fi

# Names carried by each repo. One `pacman -Sl` per repo; databases are local.
declare -A carried_by   # pkgname -> space-separated repo list, in config order
declare -A arch_home    # pkgname -> the Arch repo it would come from
for r in "${repos[@]}"; do
  while read -r _repo name _rest; do
    carried_by[$name]="${carried_by[$name]:-} $_repo"
    if _is_arch_repo "$_repo" && [[ -z ${arch_home[$name]:-} ]]; then
      arch_home[$name]=$_repo
    fi
  done < <(pacman -Sl "$r" 2>/dev/null || true)
done

# Deliberate overrides: repo:package, or repo:* for a repo whose whole job is
# to shadow Arch (the CachyOS optimised rebuilds).
declare -A allowed
if [[ -r $OVERRIDES ]]; then
  while read -r line; do
    line="${line%%#*}"; line="${line// /}"
    [[ -n $line ]] && allowed[$line]=1
  done < "$OVERRIDES"
fi
_is_allowed() { [[ -n ${allowed["$1:$2"]:-} || -n ${allowed["$1:*"]:-} ]]; }

echo "== repository order =="
for i in "${!repos[@]}"; do
  r=${repos[$i]}
  usage=$(pacman-conf --repo="$r" Usage 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  marker=""
  _is_arch_repo "$r" && marker="   <- Arch"
  printf '  %2d. %-24s %s%s\n' "$((i+1))" "$r" "${usage:-All}" "$marker"
done
echo

# --- 1. Shadowing above Arch ------------------------------------------------
# A repo ordered above core/extra/multilib that carries a name Arch also
# carries IS the source of that package now. Sometimes that is the intent
# (the v3/v4 rebuilds exist for exactly this); anything not declared is a
# silent re-sourcing of the base system.
echo "== shadowing above Arch =="
shadow_found=0
for name in "${!arch_home[@]}"; do
  home=${arch_home[$name]}
  read -r winner _ <<< "${carried_by[$name]# }"
  [[ $winner != "$home" ]] || continue
  (( ${pos[$winner]} < ${pos[$home]} )) || continue
  _is_allowed "$winner" "$name" && continue
  printf '  FAIL %-30s <- %-22s (shadows %s)\n' "$name" "$winner" "$home"
  shadow_found=1; fail=1
done
(( shadow_found )) || echo "  none beyond the declared overrides"
echo

# --- 2. Trust ---------------------------------------------------------------
echo "== signature policy =="
for r in "${repos[@]}"; do
  sig=$(pacman-conf --repo="$r" SigLevel 2>/dev/null | tr '\n' ' ')
  if [[ $sig == *TrustAll* || $sig == *Never* ]]; then
    printf '  FAIL %-24s SigLevel = %s\n' "$r" "${sig% }"
    fail=1
  fi
done
(( fail )) || echo "  every enabled repository requires signatures"
echo

# --- 3. Forbidden combinations ---------------------------------------------
echo "== forbidden combinations =="
has_alhp=0; has_cachyos_opt=0
for r in "${repos[@]}"; do
  [[ $r == *alhp* ]] && has_alhp=1
  [[ $r == cachyos-*znver* || $r == cachyos-*v3* ]] && has_cachyos_opt=1
done
if (( has_alhp && has_cachyos_opt )); then
  echo "  FAIL ALHP and the CachyOS optimised repos are both enabled."
  echo "       Both rebuild core/extra for x86-64-v3/v4. Enabled together, order"
  echo "       decides which build farm supplied each half of the base system."
  fail=1
else
  echo "  none"
fi
echo

# --- 4. Locked repos that got used -----------------------------------------
# A repo with Usage lacking Install/Upgrade should have contributed nothing.
# A package installed whose name exists ONLY there came in while unlocked.
echo "== locked repositories =="
locked_any=0
for r in "${repos[@]}"; do
  usage=$(pacman-conf --repo="$r" Usage 2>/dev/null | tr '\n' ' ')
  [[ -n $usage && $usage != *All* && $usage != *Install* ]] || continue
  locked_any=1
  leaked=0
  while read -r _repo name _rest; do
    [[ ${carried_by[$name]# } == "$r" ]] || continue      # exists nowhere else
    pacman -Qq "$name" >/dev/null 2>&1 || continue
    printf '  WARN %-28s installed, but %s is locked (%s)\n' "$name" "$r" "${usage% }"
    leaked=1; warn=1
  done < <(pacman -Sl "$r" 2>/dev/null || true)
  (( leaked )) || printf '  ok   %-24s locked (%s), nothing installed from it\n' "$r" "${usage% }"
done
(( locked_any )) || echo "  none configured"
echo

if (( fail )); then
  echo "$SELF: FAILED — see docs/REPOS.md"
  exit 1
fi
(( warn )) && echo "$SELF: passed with warnings"
(( warn )) || echo "$SELF: clean"
exit 0
