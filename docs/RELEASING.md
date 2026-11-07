# Releasing the suite

How every Magnetar repository moves to the latest versions of its
dependencies, and is released and published in an order where each crate
finds the release it depends on already out. The commands are in
`tools/suite/`; this page is the order they are run in, and why.

## The two kinds of crate

Cargo will not publish a crate that has a git dependency. libcosmic exists only
as a git repository, so the suite splits in two for good:

| Kind | Crates | Consumed as |
|---|---|---|
| **crates.io**: no toolkit | the 7 `cosmic-ext-nib-*` libraries, the 6 `cosmic-pim-*` crates, `jump-core`, `peek-engine`, `pocket-core`, the 9 publishable `locket-*` crates | `name = "X.Y"` |
| **git tag only**: link libcosmic | `cosmic-ext-widgets`, the `cosmic-ext-nib` widget, every application | `{ git = "https://github.com/Magnetar-OS/<repo>.git", tag = "vX.Y.Z" }` |

Applications are released through linux-release-kit: the tag's Release
workflow builds, signs and pushes the packages to `[magnetar]`. Crates reach
crates.io only through `tools/suite/suite-deps.sh publish`, run from the tag.

## Dependency order

```
libcosmic (git, followed through each Cargo.lock)
 ├─ cosmic-ext-nib ──────────── libraries on crates.io, widget by tag
 │   └─ cosmic-pim ──────────── crates.io (nib-text, nib-model from crates.io)
 │       └─ pocket-core ─────── crates.io, released with pocket
 └─ cosmic-ext-widgets ──────── tag
     └─ applications:
          envelope           cosmic-pim, nib (git), widgets
          pencil             nib (git), widgets
          slate, circle      cosmic-pim, widgets
          magnetar-accounts  cosmic-pim, widgets
          locket             widgets, its own locket-* crates
          pocket             pocket-core → cosmic-pim
          jump, peek         their own jump-core / peek-engine
          grabit             libcosmic only
```

Envelope takes `cosmic-ext-nib-model` and `-text` from crates.io through
cosmic-pim and from git through the nib widget. Its `[patch.crates-io]` sends
both to the same git tag, and that tag must move with the nib dependency, or
the build links two `Node` types that are not the same type.

## The ceremony

Run from the suite directory (`~/GitHub/magnetar-os`). Before each step, check
for other sessions working the same repository (`git log --since='30 minutes
ago'`, `git status`); stage with explicit paths, never `git add -A`.

**1. See what is behind.**

```sh
scripts/suite-deps.sh check
scripts/suite-deps.sh order    # the order to release in, from the manifests
```

`check` lists, per repository: requirements behind their latest release, git
dependencies on an older Magnetar-OS tag than the newest, publishable crates
whose version is not on crates.io, a newest tag with no published GitHub
release, and a followed dependency off its leader's version. It exits 1 while
anything is listed. The followed dependencies are printed at the end (see
below).

`order` prints every repository after each suite repository its crates
depend on — from crates.io, by git tag, or as a dev-dependency. Work down
that list: a repository is raised and released only once everything above
it that it uses is published. Released the other way round, a consumer
ships on the old library and has to be released again.

**2. Release the libraries, upstream first.** For each of `cosmic-ext-nib`,
then `cosmic-pim`, then `cosmic-ext-widgets`, if `check` lists it:

```sh
scripts/suite-deps.sh raise <repo>   # requirements, tags, lockfile; commits nothing
# fix whatever the new versions break; fmt --check, clippy -D warnings, tests
# commit, version, CHANGELOG section, signed tag, push
gh release create vX.Y.Z --verify-tag --title "<repo> X.Y.Z" --notes "<the version's CHANGELOG section>"
scripts/suite-deps.sh publish <repo> # crates.io, from the tag; skips what is already there
```

A library released here changes what its consumers should require, so finish
this tier before raising any application, or the applications are raised a
second time.

**3. Raise and release the applications.**

```sh
scripts/suite-deps.sh raise <app>    # picks up the libraries just released
# gate, then commit Cargo.toml, Cargo.lock and a CHANGELOG line under [Unreleased]
scripts/release-apps.sh -b patch <app>...
```

`release-apps.sh` refreshes the lockfile, runs the gates again, tags through
release-kit and then runs `suite-deps.sh publish <app>`, so jump-core,
peek-engine, pocket-core and the locket crates go to crates.io from the same
tag. It refuses to start without `CARGO_REGISTRY_TOKEN` when an app has
crates to publish, and it refuses to release an app until
`suite-deps.sh upstream <app>` passes: every suite repository the app uses
has no unreleased changes since its newest tag (lockfiles, Markdown and CI
aside), the app is on that tag, and its lockfile resolves that release of
each crates.io crate.

The locket crates share the application's version, so every locket release
publishes them. **jump-core, peek-engine and pocket-core keep versions of
their own**: raising their requirements does not change their version, and a
release of the app would leave crates.io holding the old manifest under a
version that looks current. `check` catches this by packaging each crate and
comparing it with the `.crate` crates.io serves ("changed since crates.io got
it"), and `publish` fails on it. Raise that crate's version (and the app's
`version =` for it, where there is one) in the same commit as the raised
requirements, before releasing the app.

**4. Confirm it landed.**

```sh
gh run list --repo Magnetar-OS/<app> --workflow release.yml --limit 1
scripts/suite-deps.sh check          # exits 0 when nothing is behind
```

A failed Release run is re-run with `gh run rerun <id> --failed` or
`gh workflow run release.yml -f tag=vX.Y.Z`. The tag never moves; a version
already published is never re-released — bump instead.

## Followed, not raised on their own

`raise` takes new majors like any other release. A few dependencies are
right only as the same copy another crate links, so they are not raised on
their own: they *follow* that crate. `FOLLOWS` in `suite-deps.sh` lists them
as dependency key, leader, reason. `check` verifies each links its leader's
version (`lib/suite_graph.py follows`), and `raise` puts it on that version
after everything else is upgraded, so it moves the day its leader does.

| Dependency | Follows | Because |
|---|---|---|
| `usvg` (circle, dev) | `resvg` (iced) | the tests parse with the parser iced renders with |
| `imap-proto` (cosmic-pim-mail) | `imap` | LIST and UID-set answers come back as imap-proto's types, which imap does not re-export |
| `rand_pgp` (cosmic-pim-mail, dev) | `pgp` | the tests generate keys, and pgp's key generation takes its own rand's traits |

Before 2026-11-07 the list was crates held back by hand, which hid them
from `check` until someone re-read the reasons. zbus and ashpd left it for
their latest releases (ashpd 0.14 links beside libcosmic's 0.13, since no
ashpd type crosses into libcosmic), and rsa left it when locket stopped
needing ssh-key's `rsa` feature — the feature that asked for an rsa feature
rc.20 removed.

Exact (`=`) pins exist in one place: locket's `rsa` and `ssh-key` release
candidates, which promise each other nothing; its manifest says how to move
them, and `check` lists a newer release candidate when one appears.
magnetar-web keeps `typescript` at 6.0.3 because `@astrojs/check` (0.9.12,
the newest) does not accept 7; its README says so.

## What is not a Cargo crate

- **Rust toolchain**: every repo's `rust-toolchain.toml` and `rust-version`
  name the same release. Edit those two places per repo; never a blind text
  replace, which has rewritten released changelog entries before.
- **linux-release-kit**: every app pins its workflows to one commit. Move them
  all together; read the kit's commits since the old pin for new required
  inputs, secrets or permissions first.
- **Git dependencies that follow a branch** (libcosmic, cosmic-launch,
  dbus-settings-bindings): `cargo update` moves them, and a crate can be
  renamed or moved to a new major underneath (2026-11-07: dbus-settings-bindings
  renamed `switcheroo-control` to `switcheroo-control-zbus` on zbus 6). Build
  every repository after the update, before raising anything else.
- **GitHub Actions**: the pins in each repo's `.github/workflows`.
- **magnetar-web**: `pnpm up --latest`, then `pnpm test`.
- **Distro packages** (`pkgbuilds/`): the Packages workflow publishes any
  version `[magnetar]` does not have yet; bump `pkgrel` to ship a change.
