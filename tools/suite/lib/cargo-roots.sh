# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Which directories in the suite a cargo command may be run in.
#
# Sourced, not executed. The caller sets ROOT and may set the array `excludes`,
# then calls discover_roots; it fills `roots` with the directories to act on,
# `root_skips` with lines naming what was deliberately passed over, and
# `root_foreign` with a count, per top-level directory, of resolve roots that
# belong to somebody else.
#
# This lives in one file because both cargo-update-all.sh and cargo-clean-all.sh
# need the same answer, and the rules below were each learned from a tree that
# got acted on when it should not have been. Two copies would drift.

# A resolve root is a directory holding both Cargo.toml and Cargo.lock: that
# pair is what a cargo command resolves and rewrites, and target/ is created
# beside it. Workspace members share their workspace's lock and target, so they
# are not visited separately.
#
# A manifest with no lock beside it is either such a member — nothing to report
# — or a root that has never been resolved, which is worth printing.
_covered_by_ancestor() {
    local d="$1"
    while [ "$d" != "$ROOT" ] && [ "$d" != "/" ]; do
        d="$(dirname -- "$d")"
        [ -f "$d/Cargo.lock" ] && return 0
    done
    return 1
}

# What counts as ours. A checkout here is one git repository directly under the
# suite root, so a resolve root qualifies only when its repository's top level
# is such a directory — or the root itself, so that pointing a script at a
# single project works — and the lockfile is tracked there.
#
# Both halves are needed. magnetar/build/ and pkgbuilds/*/src/ hold extracted
# and generated third-party sources; some of them (corrosion, fetched by CMake)
# arrive as git clones of their own with their own tracked lockfiles, so the
# tracked test alone lets them through and the top-level test alone lets the
# archiso output through. Either way we would be rewriting somebody else's
# build inputs in a directory makepkg deletes on the next build.
_ours() {
    local dir="$1" top
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ "$top" = "$ROOT" ] || [ "$(dirname -- "$top")" = "$ROOT" ] || return 1
    git -C "$dir" ls-files --error-unmatch Cargo.lock >/dev/null 2>&1
}

_excluded() {
    local name
    for name in ${excludes+"${excludes[@]}"}; do
        [ "$name" = "$1" ] && return 0
    done
    return 1
}

# Path as the reader should see it: relative to ROOT, or "." for ROOT itself.
rel_to_root() {
    local rel="${1#"$ROOT"/}"
    [ "$rel" = "$1" ] && rel="."
    printf '%s' "$rel"
}

roots=()
root_skips=()
declare -A root_foreign=()

discover_roots() {
    local manifest dir rel top
    # Symlinked directories are not followed, which keeps the libcosmic
    # reference checkout out of scope; it is upstream's tree, not ours to
    # touch. target/ is pruned so cargo's own vendored copies stay invisible,
    # and .worktrees/ because a git worktree there is another session's
    # checkout in progress: updating its lockfile or cleaning its target from
    # here pulls files out from under a build that is running.
    while IFS= read -r manifest; do
        dir="$(dirname -- "$manifest")"
        rel="$(rel_to_root "$dir")"
        top="${rel%%/*}"

        if _excluded "$top" || _excluded "$rel"; then
            root_skips+=("skipped  $rel (excluded)")
            continue
        fi
        if [ ! -f "$dir/Cargo.lock" ]; then
            _covered_by_ancestor "$dir" || root_skips+=("skipped  $rel (no Cargo.lock)")
            continue
        fi
        if ! _ours "$dir"; then
            # Counted, not listed: magnetar's build tree alone holds dozens of
            # these and naming each one buries the projects that were acted on.
            root_foreign["$top"]=$(( ${root_foreign["$top"]:-0} + 1 ))
            continue
        fi
        roots+=("$dir")
    done < <(find "$ROOT" \( -name target -o -name .worktrees \) -prune -o -name Cargo.toml -print | sort)
}

# The tail every caller prints: what was passed over, and why.
print_skips() {
    local top
    if [ ${#root_skips[@]} -gt 0 ]; then printf '%s\n' "${root_skips[@]}"; fi
    for top in "${!root_foreign[@]}"; do
        echo "skipped  $top: ${root_foreign[$top]} resolve roots that are build output or vendored sources"
    done
}
