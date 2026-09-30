# Magnetar

COSMIC on CachyOS, as an actual distribution: a live ISO, a pacman repository,
and the packages that make a stock CachyOS install into this one.

## What this is

CachyOS ships one desktop edition: Plasma. There is no CachyOS COSMIC edition
and no `cachyos-cosmic-settings` package. That gap is what Magnetar fills:
CachyOS's kernel, hardware detection, optimised repositories and tuning,
with COSMIC on top and a suite of COSMIC applications that do not exist
anywhere else.

| Piece | What it does |
|---|---|
| [`iso/`](iso/) | Live ISO. An **overlay** on CachyOS-Live-ISO, not a fork. |
| [`pkgbuilds/magnetar-repos`](pkgbuilds/magnetar-repos/) | Repository order, signing and locks. |
| [`pkgbuilds/magnetar-settings`](pkgbuilds/magnetar-settings/) | COSMIC session defaults, via `/etc/skel`. |
| [`pkgbuilds/magnetar-desktop`](pkgbuilds/magnetar-desktop/) | The meta package. Install it and a CachyOS machine becomes Magnetar. |
| [`pkgbuilds/apps/apps.txt`](pkgbuilds/apps/apps.txt) | The suite, for local ISO-test builds. Releases ship from each app's own repository. |
| [`pkgbuilds/magnetar-keyring`](pkgbuilds/magnetar-keyring/) | The trust root. Everything else is downstream of it. |
| [`tools/`](tools/) | The generators, the audit and the signing step. |
| [`tools/suite/`](tools/suite/) | Scripts that act on every repository checked out beside this one: the routine app release, and `cargo update` / `cargo clean` across the suite. |
| [`docs/POP-OS-ADOPTION.md`](docs/POP-OS-ADOPTION.md) | What is worth taking from Pop!_OS, and what only looks like it is. |

## Three things worth knowing before reading the code

**Repository order is the whole ballgame.** pacman takes each package from the
first repository in `pacman.conf` that carries the name and never looks lower —
a newer build underneath is simply not considered. Position *is* priority, and
it is the only lock pacman applies automatically. Magnetar enables Chaotic-AUR,
EndeavourOS and (locked, off) Valve's SteamOS repositories, so this is the part
that decides whether the distribution is stable. It is written down in
[`docs/REPOS.md`](docs/REPOS.md) and checked by `tools/repo-audit.sh` on every
change.

**Almost nothing here is hand-written.** The ISO package list is generated from
CachyOS's, the app PKGBUILDs from a manifest, the COSMIC `system_actions` map
from the installed defaults, and the repository override list from a live audit
run rather than from documentation. Hand-maintained copies of upstream files
fall behind silently, and the symptom arrives months later as an ISO that does
not boot on somebody's laptop. The ISO package list has a nightly CI job that
fails when its output is stale; the others are re-run by hand (see
Regenerating).

**The ISO is an overlay, not a fork.** `iso/sync.sh` fetches CachyOS-Live-ISO at
the commit pinned in `branding.env` and applies exact-match patches. When CachyOS changes text
we patch, the script fails and names the file. That failure is the feature —
the alternative is an ISO that is quietly wrong.

## Building

```sh
# Packages first — the ISO installs them, so nothing works without this.
tools/gen-app-pkgbuilds-local.sh           # the suite from local working trees
tools/build-local-packages.sh               # idempotent; --force to rebuild

# ISO
./iso/sync.sh                               # picks up build/repo automatically

# Confirm every name in the ISO list resolves, with its dependencies, against
# the pacman.conf sync.sh just generated — before mkarchiso spends an hour
# discovering otherwise.
tools/check-iso-packages.sh

cd build/iso-src && sudo ./buildiso.sh -p magnetar -v -w
# -> build/iso-src/out/magnetar/

# Boot it
tools/test-vm.sh --install

# Check the repository policy still holds
tools/repo-audit.sh
```

Requires `archiso mkinitcpio-archiso squashfs-tools grub git python`.

## Regenerating

Run these after the upstream they derive from moves. CI fails if you forget the
first; the second is on you.

```sh
tools/gen-iso-packages.py build/iso-src/archiso/packages_desktop.x86_64  # after bumping UPSTREAM_ISO_REF
tools/regen-system-actions.sh                                            # after a COSMIC update
```

## The suite scripts

`tools/suite/` is the one part of this repository that is not about the
distribution itself. The Magnetar repositories are checked out side by side in
one directory (the suite), and these scripts act on all of them from here, so
that the procedure behind every release has a history:

```sh
tools/suite/release-apps.sh [-n] [-b minor|patch|auto] [app...]  # rebuild against current COSMIC, gate, release
tools/suite/cargo-update-all.sh [-n] [-c]                        # cargo update in every resolve root; never commits
tools/suite/cargo-clean-all.sh [-n]                              # cargo clean in every resolve root, with sizes
```

They find the suite from their own location (`<suite>/magnetar/tools/suite`),
so they also run through the `<suite>/scripts` symlink that marks where they
used to live. `tests/suite-scripts-root.sh` runs all three against a throwaway
suite.

## Publishing

`[magnetar]` is [`Magnetar-OS/arch-repo`](https://github.com/Magnetar-OS/arch-repo),
served at `https://repo.magnetaros.com`. Each app publishes itself when it
tags a release. The packages under `pkgbuilds/` publish from
`.github/workflows/packages.yml` on every push to `main`: any version not
already in the repository is signed, added, and checked with a real
`pacman -Syw` before the push. **To ship a change to one, bump its `pkgrel`** —
an unchanged version is never republished.

The ISO is built in CI after that, not beside it: `.github/workflows/iso.yml`
runs when a Packages run on `main` has succeeded (or by hand), and first waits
until `[magnetar]` serves every package at the version this commit declares
(`tools/check-published.sh`). An ISO therefore carries the packages of the
commit it was built from, not the ones that commit was about to replace.

## State

Verified by running, on a CachyOS host:

- The overlay applies to CachyOS-Live-ISO cleanly and is idempotent
  (`tests/iso-sync.sh`). Every patch is exact-match and fails by name if
  upstream moves.
- `magnetar-repos`, `magnetar-settings`, `magnetar-desktop` and
  `magnetar-calamares` build and contain what they should.
- `tools/repo-audit.sh` runs against a live 80-repository system and reports
  true findings; the CachyOS override list was generated from that run.
- Every COSMIC config format was read off a running COSMIC 1.7.0 and
  rechecked against 1.9.0 (2026-09-28): `system_actions` still matches the
  installed defaults. The redirect and the `Spawn` action variant were
  confirmed against cosmic-comp's strings and cosmic-settings-daemon's
  `action.rs`.

Three things this turned up that were not obvious:

1. **`-C target-cpu=native`.** CachyOS ships `/etc/makepkg.conf.d/rust.conf`
   setting it. Correct for a machine building for itself; for a package other
   people install it produces a binary that SIGILLs on any older CPU. The local
   app PKGBUILDs pin a generic baseline.
2. **Testing an ISO means testing unpublished code.**
   `tools/gen-app-pkgbuilds-local.sh` stages the apps' working trees with their
   siblings and builds -git packages that provide the released names — a
   development path, not a shipping one.
3. **makepkg resolves local `source=` entries by basename**, so nested paths
   never worked. The config packages read from `$startdir` instead.

Not done yet, in the order it blocks things:

1. **No install has been run end to end in a VM.** The Calamares config
   assembly is tested against the real `cachyos-calamares-next` package
   (`tests/installer-config.sh`), and every package the installer selects
   resolves against the target's pacman.conf; whether Calamares renders
   correctly under cosmic-comp and completes an install is unknown until an
   ISO is built and booted (`tools/test-vm.sh --install`, which needs root).

## Licence

GPL-3.0-or-later, following CachyOS-Live-ISO, which `iso/` derives from.

The artwork is the exception: the wallpapers, ASCII logo, logo, installer
images and boot splashes under `pkgbuilds/magnetar-settings/`,
`pkgbuilds/magnetar-branding/`, `pkgbuilds/magnetar-calamares/branding/` and
`iso/overlay/archiso/{grub,syslinux}/` are licensed
[CC-BY-SA-4.0](https://creativecommons.org/licenses/by-sa/4.0/). Attribution:
"Magnetar artwork © the Magnetar project, https://magnetaros.com". The licence
covers copyright in the artwork; it grants no rights in the name or in the
logo as a mark.

COSMIC is a System76 trademark. Nothing here is named `cosmic-*`, and the
distribution does not claim to be a COSMIC product.
