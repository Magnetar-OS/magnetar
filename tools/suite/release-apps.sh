#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Rebuild the suite's applications against the current COSMIC stack and cut a
# release of each.
#
# COSMIC moves fast and every application links libcosmic by git, so a
# routine release is: move each lockfile to the tip of libcosmic and friends,
# prove the result passes the same gates the release pipeline runs, commit the
# lockfile with a changelog line naming the libcosmic it now builds against,
# and hand the repository to release-kit, whose pushed tag starts the
# pipeline that builds, signs and publishes the packages.
#
# Applications go one at a time and the run stops at the first failure: a
# broken app is left with its lockfile updated and uncommitted, for someone to
# look at, and everything after it is untouched. Re-running is safe: an app with
# nothing to release — libcosmic did not move and [Unreleased] is empty, as for
# one the previous run already released — is skipped, and the run goes on to
# the next. Its lockfile, if other crates moved, is left uncommitted.
#
# Library crates are not released here. The cosmic-pim, jump-core,
# peek-engine and pocket-core crates are toolkit-free and version on their own
# schedule; cosmic-ext-widgets and cosmic-ext-nib are consumed by git tag, and
# a new libcosmic reaches the applications through their own lockfiles
# whether or not those tags move.
set -euo pipefail

# The suite is the directory the magnetar repository is checked out in, beside
# the applications: this file is <suite>/magnetar/tools/suite/<script>. Resolved
# physically, so starting it through the <suite>/scripts symlink gives the
# same answer.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$HERE/../../.." && pwd)"
RELEASE_KIT="${RELEASE_KIT:-$HOME/GitHub/release-kits/release-kit/release.mjs}"
ALL_APPS=(grabit circle envelope jump peek slate locket pencil pocket)

usage() {
    cat <<'USAGE'
usage: release-apps.sh [options] [app...]

Updates each app's lockfile, runs fmt, clippy -D warnings and the tests,
commits the lockfile, and releases the app with release-kit. With no app
named, every suite application is released.

options:
  -b, --bump KIND   release-kit target: patch, minor (default), major, auto
  -n, --dry-run     update and check everything a real run checks, then show
                    release-kit's plan; the lockfiles are left uncommitted,
                    nothing is committed or pushed, and the exit status says
                    whether the real run would get through
  -h, --help        this text
USAGE
}

bump=minor
dry_run=0
apps=()
while [ $# -gt 0 ]; do
    case "$1" in
        -b|--bump)    [ $# -ge 2 ] || { usage >&2; exit 2; }; bump="$2"; shift 2 ;;
        -n|--dry-run) dry_run=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            apps+=("$1"); shift ;;
    esac
done
[ ${#apps[@]} -gt 0 ] || apps=("${ALL_APPS[@]}")
[ -f "$RELEASE_KIT" ] || { echo "release-kit not found at $RELEASE_KIT (set RELEASE_KIT)" >&2; exit 1; }

# The lockfiles a cargo update may rewrite: the app's own, and a fuzz
# workspace's when it has one.
lockfiles() {
    git -C "$1" ls-files -- Cargo.lock fuzz/Cargo.lock
}

# The libcosmic commit a lockfile resolves, short, read from stdin. Reads all
# of it: stopping at the first match would SIGPIPE the writer under pipefail.
# Prints nothing, successfully, for a lockfile without libcosmic.
libcosmic_rev() {
    { grep -oE 'pop-os/libcosmic(\.git)?#[0-9a-f]{7}' || true; } | sed -n '1s/.*#//p'
}

# Whether [Unreleased] in CHANGELOG.md has at least one entry.
has_unreleased() {
    awk '/^## \[Unreleased\]/{on=1; next} /^## /{on=0} on && /^- /{found=1} END{exit !found}' "$1/CHANGELOG.md"
}

# Adds a line to [Unreleased] saying which libcosmic the app now builds
# against, under the section's existing "### Changed" when it has one.
note_rebuild() {
    python3 - "$1/CHANGELOG.md" "$2" <<'PY'
import re, sys
path, rev = sys.argv[1], sys.argv[2]
text = open(path).read()
line = f"- Rebuilt against the current COSMIC libraries (libcosmic `{rev}`).\n"
head = re.search(r"^## \[Unreleased\][^\n]*\n", text, re.M)
if not head:
    sys.exit(f"{path}: no [Unreleased] section")
end = re.compile(r"^## ", re.M).search(text, head.end())
end = end.start() if end else len(text)
changed = re.compile(r"^### Changed[^\n]*\n\n?", re.M).search(text, head.end(), end)
if changed:
    at, insert = changed.end(), line
else:
    at, insert = head.end(), "\n### Changed\n\n" + line
open(path, "w").write(text[:at] + insert + text[at:])
PY
}

skipped=()
dry_failed=()
for app in "${apps[@]}"; do
    dir="$ROOT/$app"
    [ -d "$dir/.git" ] || { echo "$app: not a repository under $ROOT" >&2; exit 1; }
    echo
    echo "==> $app"

    # Anything dirty beyond the lockfiles is somebody's unfinished work, and
    # release-kit would refuse it anyway — say so before spending a build.
    dirty="$(git -C "$dir" status --porcelain | grep -vE '^ M (fuzz/)?Cargo\.lock$' || true)"
    if [ -n "$dirty" ]; then
        echo "$app: uncommitted changes besides the lockfiles:" >&2
        echo "$dirty" >&2
        exit 1
    fi

    # A release is tagged on this HEAD and pushed; one behind its upstream
    # would either be rejected or release without somebody's commits.
    git -C "$dir" fetch --quiet
    behind="$(git -C "$dir" rev-list --count 'HEAD..@{upstream}')"
    if [ "$behind" -ne 0 ]; then
        echo "$app: $behind commit(s) behind $(git -C "$dir" rev-parse --abbrev-ref '@{upstream}'); pull first" >&2
        exit 1
    fi

    # From the last release, not HEAD or the working tree: a lockfile
    # somebody already updated — committed or not — has moved since that
    # release all the same, and its changelog should say so.
    last="$(git -C "$dir" describe --tags --abbrev=0)"
    before="$(git -C "$dir" show "$last:Cargo.lock" | libcosmic_rev)"
    (cd "$dir" && cargo update --quiet)
    [ ! -f "$dir/fuzz/Cargo.lock" ] || (cd "$dir/fuzz" && cargo update --quiet)
    after="$(libcosmic_rev <"$dir/Cargo.lock")"
    echo "libcosmic: ${before:-?} -> ${after:-?}"

    # The pipeline's own gates, so a release cannot fail on them after the
    # tag is already public.
    (cd "$dir" && cargo fmt --check && cargo clippy --locked -- -D warnings && cargo test --locked --quiet)

    # Named in the changelog only when libcosmic itself moved; other
    # dependency churn is not something a user sees.
    note=0
    if [ "$before" != "$after" ] && ! grep -qF "libcosmic \`$after\`" "$dir/CHANGELOG.md"; then
        note=1
    fi

    # The pipeline takes the release body from the version's changelog
    # section and refuses a tag without one; release-kit writes no section
    # from an empty [Unreleased]. An app with nothing to say has nothing to
    # release — typically one the previous run already released — so it is
    # skipped rather than tagged, and the run goes on.
    if [ "$note" -eq 0 ] && ! has_unreleased "$dir"; then
        echo "$app: nothing to release (libcosmic unchanged, [Unreleased] empty); skipped"
        skipped+=("$app")
        continue
    fi

    if [ "$dry_run" -eq 1 ]; then
        [ "$note" -eq 0 ] || echo "would add to CHANGELOG.md: libcosmic \`$after\`"
        # release-kit's own preflight, reported rather than swallowed: a dry
        # run that says "checked" for an app the real run refuses is worse
        # than none.
        if ! (cd "$dir" && node "$RELEASE_KIT" "$bump" --dry-run --skip commit); then
            echo "$app: release-kit's dry run failed; the real run would stop here" >&2
            dry_failed+=("$app")
        fi
        continue
    fi

    mapfile -t locks < <(lockfiles "$dir")
    paths=()
    git -C "$dir" diff --quiet -- "${locks[@]}" || paths+=("${locks[@]}")
    if [ "$note" -eq 1 ]; then
        note_rebuild "$dir" "$after"
        paths+=(CHANGELOG.md)
    fi
    if [ ${#paths[@]} -gt 0 ]; then
        # Only these paths, whatever else is staged: the gates above take
        # minutes, and another session may have staged work in the meantime.
        git -C "$dir" commit --quiet -m "chore(deps): build against libcosmic $after" -- "${paths[@]}"
    fi

    (cd "$dir" && node "$RELEASE_KIT" "$bump" --yes)
done

released=()
for app in "${apps[@]}"; do
    case " ${skipped[*]-} ${dry_failed[*]-} " in *" $app "*) ;; *) released+=("$app") ;; esac
done

echo
[ ${#skipped[@]} -eq 0 ] || echo "Skipped, nothing to release: ${skipped[*]}"
if [ "$dry_run" -eq 1 ]; then
    [ ${#released[@]} -eq 0 ] || echo "Dry run: ${released[*]} would be released; lockfiles left uncommitted, nothing tagged."
    if [ ${#dry_failed[@]} -gt 0 ]; then
        echo "Dry run: release-kit refused ${dry_failed[*]}." >&2
        exit 1
    fi
elif [ ${#released[@]} -gt 0 ]; then
    echo "Released: ${released[*]}. The tags start each repository's Release workflow;"
    echo "watch them with: gh run list --repo Magnetar-OS/<app> --workflow release.yml"
fi
