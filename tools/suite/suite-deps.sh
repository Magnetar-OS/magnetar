#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Keep the suite's dependencies at their latest versions, and its crates
# published, in the order docs/RELEASING.md lays out.
#
#   check            report every requirement behind its latest release, every
#                    Magnetar-OS git dependency on an older tag than the newest,
#                    every publishable crate whose version is not on crates.io
#                    or whose content changed since that version was
#                    published, and every repository whose newest tag has no published
#                    GitHub release; exits 1 when anything is behind
#   raise [repo...]  move those requirements and tags to the newest and refresh
#                    the lockfiles; commits nothing
#   publish REPO     publish REPO's crates that crates.io does not have yet,
#                    from a clean worktree of REPO's newest tag; fails when a
#                    crate changed under a version crates.io already has
#
# Requirements are raised with `cargo upgrade --incompatible allow`, so a new
# major is taken like any other release. The crates in COUPLED are the
# exception: each must stay on the version another crate links, and moves only
# when that crate does. Re-check the list whenever libcosmic, imap or pgp move.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$HERE/../../.." && pwd)"
# Where the suite's repositories are published; tests/suite-scripts-root.sh
# points it at local bare repositories.
ORG_URL="${SUITE_ORG_URL:-https://github.com/Magnetar-OS}"

# name  why it is held
COUPLED=(
    "zbus        libcosmic, ashpd and dbus-settings-bindings are on zbus 5, and apps pass zvariant values through libcosmic"
    "ashpd       pencil and pocket share libcosmic's copy so no second one is linked"
    "usvg        circle's tests parse with the copy iced's resvg links"
    "imap-proto  imap 3.0.0-alpha.15 requires 0.16, and LIST attributes come back as its types"
    "rand        cosmic-pim-mail's rand_pgp is the rand pgp 0.21 requires (0.8)"
)

usage() {
    cat <<'USAGE'
usage: suite-deps.sh check
       suite-deps.sh raise [repo...]
       suite-deps.sh publish REPO

check    report requirements, Magnetar-OS tags, crates.io versions and GitHub
         releases that are behind; exit 1 when anything is
raise    raise requirements to their latest releases (except the coupled
         crates), move Magnetar-OS tags to the newest, refresh the lockfiles;
         every repo when none is named; commits nothing
publish  publish REPO's crates that crates.io lacks, from REPO's newest tag;
         needs CARGO_REGISTRY_TOKEN
USAGE
}

coupled_flags() {
    local entry
    for entry in "${COUPLED[@]}"; do printf -- '--exclude\n%s\n' "${entry%% *}"; done
}

# The newest vX.Y.Z tag a repository has pushed.
latest_tag() {
    git ls-remote --tags --refs "$ORG_URL/$1.git" 'v*' | sed 's#.*refs/tags/##' | sort -V | tail -n1
}

# Whether crates.io has NAME at VERSION, read from the sparse index.
on_crates_io() {
    local name="$1" version="$2" path
    case ${#name} in
        1) path="1/$name" ;;
        2) path="2/$name" ;;
        3) path="3/${name:0:1}/$name" ;;
        *) path="${name:0:2}/${name:2:2}/$name" ;;
    esac
    curl -fsS "https://index.crates.io/$path" 2>/dev/null |
        grep -qF "\"vers\":\"$version\""
}

# Whether the crate NAME at VERSION, packaged from the workspace at $1 as it
# stands, differs from what crates.io serves for that version. A crate that
# versions on its own (jump-core, peek-engine, pocket-core) can change while
# its version stays put, and crates.io then holds the old manifest under a
# version that looks current. The packaged Cargo.toml has workspace
# inheritance resolved, so a requirement raised in the workspace shows too.
# Cargo.lock is left out: a published binary's lock moves on every refresh.
changed_since_published() {
    local dir="$1" name="$2" version="$3" tmp differs=1
    tmp="$(mktemp -d)"
    mkdir "$tmp/published" "$tmp/local"
    if curl -fsSL "https://static.crates.io/crates/$name/$name-$version.crate" | tar xz -C "$tmp/published" &&
        (cd -- "$dir" && cargo package --quiet -p "$name" --no-verify --allow-dirty --target-dir "$tmp/target") &&
        tar xzf "$tmp/target/package/$name-$version.crate" -C "$tmp/local"; then
        diff -rq --exclude=.cargo_vcs_info.json --exclude=Cargo.toml.orig --exclude=Cargo.lock \
            "$tmp/published/$name-$version" "$tmp/local/$name-$version" >/dev/null || differs=0
    else
        echo "  $name $version: could not compare with crates.io" >&2
        differs=0
    fi
    rm -rf -- "$tmp"
    return "$differs"
}

# "name version" for each crate in the workspace at $1 that may be published.
publishable() {
    (cd -- "$1" && cargo metadata --no-deps --format-version 1) |
        python3 -c 'import json,sys
for p in json.load(sys.stdin)["packages"]:
    if p.get("publish") != []: print(p["name"], p["version"])'
}

# Rewrites every Magnetar-OS git dependency in the repo at $1 to that
# repository's newest tag. With $2 = check, rewrites nothing and prints the
# stale ones instead.
suite_tags() {
    local dir="$1" mode="${2:-raise}" manifest repo tag newest stale=0
    while IFS= read -r manifest; do
        while read -r repo tag; do
            newest="$(latest_tag "$repo")"
            [ -n "$newest" ] && [ "$tag" != "$newest" ] || continue
            if [ "$mode" = check ]; then
                echo "  $(rel_to_root "$dir/$manifest"): $repo $tag -> $newest"
                stale=1
            else
                sed -i -E "s#($ORG_URL/$repo\\.git\", tag = \")$tag\"#\\1$newest\"#g" "$dir/$manifest"
            fi
        done < <(grep -oE "Magnetar-OS/[a-z0-9-]+\\.git\", tag = \"v[0-9.]+\"" "$dir/$manifest" |
                 sed -E 's#Magnetar-OS/([a-z0-9-]+)\.git", tag = "(v[0-9.]+)"#\1 \2#' | sort -u)
    done < <(git -C "$dir" ls-files -- 'Cargo.toml' '*/Cargo.toml')
    return "$stale"
}

cmd_check() {
    local dir rel behind=0 rows name version tag
    mapfile -t ex < <(coupled_flags)
    for dir in "${roots[@]}"; do
        rel="$(rel_to_root "$dir")"
        echo "==> $rel"
        # cargo-edit prints one table per manifest; any row under a header is
        # a requirement behind its latest release.
        rows="$(cd -- "$dir" && cargo upgrade --dry-run --incompatible allow --pinned allow "${ex[@]}" 2>/dev/null |
                awk '/^====/{t=1; next} /^name /{next} t && NF>=4 {print "  " $0} /^$/{t=0}')"
        if [ -n "$rows" ]; then echo "$rows"; behind=1; fi
        suite_tags "$dir" check || behind=1
        # A fuzz workspace's crates are never published, and only a
        # repository's top level has releases.
        [ "$(dirname -- "$dir")" = "$ROOT" ] || continue
        tag="$(latest_tag "$(basename -- "$dir")")"
        if [ -n "$tag" ] &&
            [ "$(gh release view "$tag" --repo "${ORG_URL#https://github.com/}/$(basename -- "$dir")" --json isDraft --jq .isDraft 2>/dev/null)" != false ]; then
            echo "  no published GitHub release for $tag"
            behind=1
        fi
        while read -r name version; do
            if ! on_crates_io "$name" "$version"; then
                echo "  unpublished: $name $version"
                behind=1
            elif changed_since_published "$dir" "$name" "$version"; then
                echo "  changed since crates.io got it: $name $version (raise its version)"
                behind=1
            fi
        done < <(publishable "$dir")
    done
    echo
    echo "held on purpose:"
    printf '  %s\n' "${COUPLED[@]}"
    return "$behind"
}

cmd_raise() {
    local dir
    mapfile -t ex < <(coupled_flags)
    for dir in "${roots[@]}"; do
        echo "==> $(rel_to_root "$dir")"
        suite_tags "$dir"
        (cd -- "$dir" && cargo upgrade --incompatible allow "${ex[@]}" && cargo update)
    done
}

cmd_publish() {
    local repo="$1" dir="$ROOT/$1" tag tree name version todo=() stale=()
    [ -d "$dir/.git" ] || { echo "$repo: not a repository under $ROOT" >&2; exit 1; }
    git -C "$dir" fetch --quiet --tags
    tag="$(git -C "$dir" describe --tags --abbrev=0)"
    if [ -z "$(publishable "$dir")" ]; then
        echo "$repo $tag: no crate to publish"
        return
    fi
    # From the tag, not the working tree: what crates.io gets is what the tag
    # says was released, whatever is in progress in the shared checkout.
    tree="$(mktemp -d)"
    git -C "$dir" worktree add --quiet --detach "$tree" "$tag"
    # Expanded now: the locals are gone by the time the EXIT trap runs.
    # shellcheck disable=SC2064
    trap "git -C '$dir' worktree remove --force '$tree'" EXIT
    while read -r name version; do
        if ! on_crates_io "$name" "$version"; then
            todo+=(-p "$name")
        elif changed_since_published "$tree" "$name" "$version"; then
            stale+=("$name $version")
        fi
    done < <(publishable "$tree")
    if [ ${#todo[@]} -gt 0 ]; then
        [ -n "${CARGO_REGISTRY_TOKEN:-}" ] || { echo "$repo $tag: CARGO_REGISTRY_TOKEN is not set" >&2; exit 1; }
        echo "$repo $tag: publishing ${todo[*]//-p /}"
        # cargo orders several -p by their dependencies and waits for each to
        # reach the index before the crates that need it.
        (cd -- "$tree" && CARGO_TARGET_DIR="$dir/target" cargo publish --locked "${todo[@]}")
    fi
    if [ ${#stale[@]} -gt 0 ]; then
        echo "$repo $tag: changed since crates.io got them, under the same version:" >&2
        printf '  %s\n' "${stale[@]}" >&2
        echo "raise their versions, release $repo again, and publish" >&2
        exit 1
    fi
    [ ${#todo[@]} -gt 0 ] || echo "$repo $tag: every publishable crate is on crates.io"
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command -v cargo-upgrade >/dev/null || { echo "cargo-upgrade not found: cargo install cargo-edit" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
# shellcheck source=lib/cargo-roots.sh
. "$HERE/lib/cargo-roots.sh"

# magnetar/build/ holds root-owned ISO trees that find cannot enter; they are
# build output, which discover_roots passes over anyway.
case "$1" in
    check)
        discover_roots 2>/dev/null
        cmd_check ;;
    raise)
        shift
        discover_roots 2>/dev/null
        if [ $# -gt 0 ]; then
            keep=()
            for repo in "$@"; do
                [ -d "$ROOT/$repo/.git" ] || { echo "$repo: not a repository under $ROOT" >&2; exit 1; }
                for dir in "${roots[@]}"; do
                    case "$dir/" in "$ROOT/$repo/"*) keep+=("$dir") ;; esac
                done
            done
            roots=("${keep[@]}")
        fi
        cmd_raise ;;
    publish)
        [ $# -eq 2 ] || { usage >&2; exit 2; }
        cmd_publish "$2" ;;
    -h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
