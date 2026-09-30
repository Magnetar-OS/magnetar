#!/usr/bin/env bash
#
# Which packages in a pacman repository database are replaced by another
# package in the same database?
#
#   tools/repo-superseded.sh <repo>.db.tar.gz
#
# Prints one name per line. A renamed package declares the old name in
# replaces=(): the previewer became magnetar-peek with `peek<=1.0.1`, the
# editor magnetar-pencil with `pencil<=1.2.0`. pacman acts on that when a
# machine upgrades — but the old package's last version stays in the
# repository, still installable by name and still colliding with whatever
# other repository made the rename necessary. Retention never reaches it,
# because retention counts versions of one name and the old name gets no new
# ones.
#
# A versioned constraint is honoured, as pacman honours it: `pencil<=1.2.0`
# does not supersede a `pencil 3.0` that somebody published on purpose.
set -euo pipefail

db="${1:?usage: repo-superseded.sh <repo>.db.tar.gz}"
[[ -r $db ]] || { echo "repo-superseded: $db not found" >&2; exit 2; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
bsdtar -xf "$db" -C "$w"

# The lines of one %FIELD% block of a desc file.
field() { awk -v f="%$1%" '$0 == f {on = 1; next} /^$/ {on = 0} on' "$2"; }

declare -A version
for desc in "$w"/*/desc; do
  [[ -f $desc ]] || continue
  version["$(field NAME "$desc")"]="$(field VERSION "$desc")"
done

for desc in "$w"/*/desc; do
  [[ -f $desc ]] || continue
  by="$(field NAME "$desc")"
  while read -r dep; do
    [[ -n $dep ]] || continue
    if [[ $dep =~ ^([^\<\>=]+)(\<=|\>=|=|\<|\>)(.+)$ ]]; then
      name=${BASH_REMATCH[1]} op=${BASH_REMATCH[2]} bound=${BASH_REMATCH[3]}
    else
      name=$dep op="" bound=""
    fi
    [[ $name != "$by" && -n ${version[$name]:-} ]] || continue
    if [[ -n $op ]]; then
      cmp="$(vercmp "${version[$name]}" "$bound")"
      case "$op" in
        '<=') (( cmp <= 0 )) ;;
        '>=') (( cmp >= 0 )) ;;
        '=')  (( cmp == 0 )) ;;
        '<')  (( cmp <  0 )) ;;
        '>')  (( cmp >  0 )) ;;
      esac || continue
    fi
    printf '%s\n' "$name"
  done < <(field REPLACES "$desc")
done | sort -u
