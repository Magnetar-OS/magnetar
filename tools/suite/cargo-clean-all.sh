#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Run `cargo clean` in every Cargo resolve root under the suite, and say how
# much disk each one gave back.
#
# Which directories those are, and which are somebody else's, is decided by
# lib/cargo-roots.sh — the same answer this shares with cargo-update-all.sh.
# That matters more here than there: magnetar/build/ and pkgbuilds/*/src/ are
# full of other people's build trees, and this command deletes rather than
# rewrites.
#
# Each root is entered with `cd` rather than addressed with --manifest-path,
# so its rust-toolchain.toml selects the toolchain and cargo resolves the same
# target directory a build in that checkout would have used.
#
# What this costs is rebuild time, and nothing else: target/ is derived, it is
# git-ignored in every checkout here, and `cargo build` reproduces it. Sizes
# are measured with du before and after rather than read out of cargo's own
# summary, so the number is the one the filesystem agrees with.
set -euo pipefail

# The suite is the directory the magnetar repository is checked out in, beside
# the applications: this file is <suite>/magnetar/tools/suite/<script>. Resolved
# physically, so starting it through the <suite>/scripts symlink gives the
# same answer.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$HERE/../../.." && pwd)"
dry_run=0
dry_flag=()      # "0" is a non-empty string, so ${dry_run:+...} would fire on
dry_note=""      # it and dry-run every run; the flag travels in its own array
excludes=()

usage() {
    cat <<'USAGE'
usage: cargo-clean-all.sh [options] [root]

Runs `cargo clean` in every directory under <root> that has a Cargo.toml and
a tracked Cargo.lock. Default root is the suite: the directory the magnetar
repository is checked out in. Reports the disk each root freed, and the total.

options:
  -n, --dry-run        report what each target/ holds, delete nothing
  -x, --exclude NAME   skip the project directory NAME (repeatable)
  -h, --help           this text
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) dry_run=1; dry_flag=(--dry-run); dry_note=", dry run"; shift ;;
        -x|--exclude) [ $# -ge 2 ] || { usage >&2; exit 2; }; excludes+=("$2"); shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            ROOT="$(cd -- "$1" && pwd)"; shift ;;
    esac
done

command -v cargo >/dev/null || { echo "cargo not on PATH" >&2; exit 1; }
# shellcheck source=lib/cargo-roots.sh
. "$HERE/lib/cargo-roots.sh"
discover_roots

# Apparent size, not blocks: this is "how much was written", which is the
# number that matches what cargo will have to build again. du still prints
# its total when it cannot read part of the tree, and exits 1; that is a
# number to report, not a reason to end the whole run.
bytes_of() {
    [ -d "$1" ] || { printf '0'; return; }
    { du -sb -- "$1" 2>/dev/null || true; } | cut -f1
}

# Where this root's builds go: target/ beside it unless CARGO_TARGET_DIR or a
# build.target-dir in some .cargo/config.toml says otherwise. cargo metadata
# answers with the same rules a build uses; without it, fall back to target/.
target_of() {
    local t
    t="$(cd -- "$1" && cargo metadata --format-version 1 --no-deps --offline 2>/dev/null \
         | python3 -c 'import json, sys; print(json.load(sys.stdin)["target_directory"])' 2>/dev/null)" || t=""
    printf '%s' "${t:-$1/target}"
}
human() { numfmt --to=iec --suffix=B --format='%.1f' -- "$1"; }

report=()
failures=0
total=0

for dir in ${roots+"${roots[@]}"}; do
    rel="$(rel_to_root "$dir")"
    target="$(target_of "$dir")"
    shown="${target#"$dir"/}"
    before="$(bytes_of "$target")"

    if [ "$before" -eq 0 ]; then
        report+=("clean    $rel (nothing in $shown)")
        continue
    fi

    echo
    echo "==> $rel ($(human "$before") in $shown)"
    if (cd -- "$dir" && cargo clean ${dry_flag+"${dry_flag[@]}"}); then
        if [ "$dry_run" -eq 1 ]; then
            total=$(( total + before ))
            report+=("ok       $rel ($(human "$before") would be freed$dry_note)")
        else
            # Measured again rather than assumed: cargo leaves target/ behind
            # when something in it is held open, and that should show as a
            # smaller number, not as a clean sweep.
            freed=$(( before - $(bytes_of "$target") ))
            total=$(( total + freed ))
            report+=("ok       $rel ($(human "$freed") freed)")
        fi
    else
        report+=("FAILED   $rel (cargo clean failed)")
        failures=$((failures + 1))
    fi
done

echo
echo "=== summary (root: $ROOT)"
if [ ${#report[@]} -gt 0 ]; then printf '%s\n' "${report[@]}"; fi
print_skips
echo
if [ "$dry_run" -eq 1 ]; then
    echo "dry run: nothing was deleted. $(human "$total") would be freed."
else
    echo "$(human "$total") freed. Next build in each checkout is a full one."
fi
exit $(( failures > 0 ))
