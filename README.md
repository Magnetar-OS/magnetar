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
| [`pkgbuilds/apps/`](pkgbuilds/apps/) | The suite, packaged from git until it tags. |
| [`pkgbuilds/magnetar-keyring`](pkgbuilds/magnetar-keyring/) | The trust root. Everything else is downstream of it. |
| [`tools/`](tools/) | The generators, the audit and the signing step. |
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
not boot on somebody's laptop. Every generator has a CI job that fails when its
output is stale.

**The ISO is an overlay, not a fork.** `iso/sync.sh` clones CachyOS-Live-ISO at
the pinned ref and applies eight exact-match patches. When CachyOS changes text
we patch, the script fails and names the file. That failure is the feature —
the alternative is an ISO that is quietly wrong.

## Building

```sh
# Packages first — the ISO installs them, so nothing works without this.
tools/gen-app-pkgbuilds-local.sh ~/GitHub   # until the suite is pushed
tools/build-local-packages.sh               # idempotent; --force to rebuild

# Confirm every name in the ISO list resolves, before mkarchiso spends an hour
# discovering otherwise.
tools/check-iso-packages.sh

# ISO
./iso/sync.sh                               # picks up build/repo automatically
cd build/iso-src && sudo ./buildiso.sh -p magnetar -v -w
# -> build/iso-src/out/magnetar/

# Boot it
tools/test-vm.sh --install

# Check the repository policy still holds
tools/repo-audit.sh
```

Requires `archiso mkinitcpio-archiso squashfs-tools grub git python`.

## Regenerating

Run these after the upstream they derive from moves. CI fails if you forget.

```sh
tools/gen-iso-packages.py build/iso-src/archiso/packages_desktop.x86_64  # after bumping UPSTREAM_ISO_REF
tools/gen-app-pkgbuilds.sh                                               # after editing pkgbuilds/apps/apps.txt
tools/regen-system-actions.sh                                            # after a COSMIC update
```

## State

Verified by running, on a CachyOS host:

- The overlay applies to CachyOS-Live-ISO cleanly and is idempotent. Eight
  exact-match patches, each of which fails by name if upstream moves.
- `magnetar-repos`, `magnetar-settings`, `magnetar-desktop` and
  `magnetar-calamares` build and contain what they should.
- `tools/repo-audit.sh` runs against a live 80-repository system and reports
  true findings; the CachyOS override list was generated from that run.
- Every COSMIC config format was read off a running COSMIC 1.7.0. The
  `system_actions` redirect and the `Spawn` action variant were confirmed
  against cosmic-comp's strings and cosmic-settings-daemon's `action.rs`.

Three things this turned up that were not obvious:

1. **`-C target-cpu=native`.** CachyOS ships `/etc/makepkg.conf.d/rust.conf`
   setting it. Correct for a machine building for itself; for a package other
   people install it produces a binary that SIGILLs on any older CPU. The app
   PKGBUILDs pin a generic baseline.
2. **The suite cannot be packaged from git yet.** `peek` and `grabit` have no
   commits; `circle`, `slate` and `envelope` depend on `cosmic-pim` by relative
   path, so no single-repo clone resolves. Hence
   `tools/gen-app-pkgbuilds-local.sh`, which stages working trees with their
   siblings — a development path, not a shipping one.
3. **makepkg resolves local `source=` entries by basename**, so nested paths
   never worked. The config packages read from `$startdir` instead.

Not done yet, in the order it blocks things:

1. **The suite is not on GitHub.** All seven repositories 404. Until they are
   pushed, the committed PKGBUILDs cannot build and only the local path works.
2. **`magnetar-repo` does not exist**, so `[magnetar]` is configured and
   unserved. `iso/sync.sh` falls back to a local directory over `file://` with
   signatures relaxed *in the build tree only*.
4. **Calamares is branded but untested.** The config assembly asserts on
   CachyOS's text; whether it renders correctly under cosmic-comp is unknown
   until an ISO boots.
5. **Per-app dependencies are the libcosmic base set only.** namcap runs in CI
   and reports the rest.

## Licence

GPL-3.0-or-later, following CachyOS-Live-ISO, which `iso/` derives from.

COSMIC is a System76 trademark. Nothing here is named `cosmic-*`, and the
distribution does not claim to be a COSMIC product.
