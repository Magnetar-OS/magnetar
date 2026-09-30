#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Run `cargo update` in every Cargo resolve root under the suite.
#
# Which directories those are, and which are somebody else's, is decided by
# lib/cargo-roots.sh — the same answer this shares with cargo-clean-all.sh.
#
# Each root is entered with `cd` rather than addressed with --manifest-path so
# that its rust-toolchain.toml selects the toolchain, the same way CI resolves
# it.
#
# This script never commits. Several checkouts here are shared, so the lock
# changes are left in the working tree for whoever is driving to inspect.
#
# Note what a full update means for this suite: the git dependencies
# (libcosmic and the COSMIC crates) move to the tip of their tracked branch,
# not to a semver-compatible release. That is the change most likely to break
# a build, so pass --check when you want the answer in the same run.
set -euo pipefail

# The suite is the directory the magnetar repository is checked out in, beside
# the applications: this file is <suite>/magnetar/tools/suite/<script>. Resolved
# physically, so starting it through the <suite>/scripts symlink gives the
# same answer.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$HERE/../../.." && pwd)"
dry_run=0
dry_flag=()      # what cargo is actually given; "0" is a non-empty string, so
dry_note=""      # ${dry_run:+...} would fire on it and dry-run every run
run_check=0
excludes=()

usage() {
    cat <<'USAGE'
usage: cargo-update-all.sh [options] [root]

Runs `cargo update` in every directory under <root> that has a Cargo.toml and
a tracked Cargo.lock. Default root is the suite: the directory the magnetar
repository is checked out in.

options:
  -n, --dry-run        show what cargo would update, write nothing
  -x, --exclude NAME   skip the project directory NAME (repeatable)
  -c, --check          run `cargo check --workspace --all-targets` after a
                       successful update, so a broken bump is visible here
  -h, --help           this text
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) dry_run=1; dry_flag=(--dry-run); dry_note=", dry run"; shift ;;
        -x|--exclude) [ $# -ge 2 ] || { usage >&2; exit 2; }; excludes+=("$2"); shift 2 ;;
        -c|--check)   run_check=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            ROOT="$(cd -- "$1" && pwd)"; shift ;;
    esac
done

command -v cargo >/dev/null || { echo "cargo not on PATH" >&2; exit 1; }
# shellcheck source=lib/cargo-roots.sh
. "$HERE/lib/cargo-roots.sh"
discover_roots

report=()
failures=0

for dir in ${roots+"${roots[@]}"}; do
    rel="$(rel_to_root "$dir")"
    echo
    echo "==> $rel"
    # Cargo writes the per-package "Updating foo v1 -> v2" lines to stderr; they
    # are the only evidence of what moved, so they are teed rather than counted
    # from the lockfile diff, which would also show transitive churn.
    output="$(mktemp)"
    if (cd -- "$dir" && cargo update ${dry_flag+"${dry_flag[@]}"}) 2>&1 | tee "$output"; then
        moved="$(grep -cE '^\s+(Updating|Adding|Removing|Downgrading) ' "$output" || true)"
        if [ "$run_check" -eq 1 ] && [ "$dry_run" -eq 0 ]; then
            echo "--- cargo check $rel"
            if (cd -- "$dir" && cargo check --workspace --all-targets); then
                report+=("ok       $rel ($moved changed, check passed)")
            else
                report+=("BROKEN   $rel ($moved changed, cargo check FAILED)")
                failures=$((failures + 1))
            fi
        else
            report+=("ok       $rel ($moved changed$dry_note)")
        fi
    else
        report+=("FAILED   $rel (cargo update failed)")
        failures=$((failures + 1))
    fi
    rm -f "$output"
done

echo
echo "=== summary (root: $ROOT)"
if [ ${#report[@]} -gt 0 ]; then printf '%s\n' "${report[@]}"; fi
print_skips
echo
if [ "$dry_run" -eq 1 ]; then
    echo "dry run: no lockfile was written."
else
    echo "Lockfiles are left uncommitted; review each repo's Cargo.lock diff before committing."
fi
exit $(( failures > 0 ))
