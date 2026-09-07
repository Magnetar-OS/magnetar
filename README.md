# Pharos

COSMIC on CachyOS, as an actual distribution: a live ISO, a pacman repository,
and the packages that make a stock CachyOS install into this one.

> **The name is a placeholder.** `pharos` is a stand-in until the real name is
> settled. Everything that names the distribution reads `branding.env`, so the
> rename is one commit — but do it before the first public ISO, not after.

## What this is

CachyOS ships one desktop edition: Plasma. There is no CachyOS COSMIC edition
and no `cachyos-cosmic-settings` package. That gap is what Pharos fills:
CachyOS's kernel, hardware detection, optimised repositories and tuning,
with COSMIC on top and a suite of COSMIC applications that do not exist
anywhere else.

| Piece | What it does |
|---|---|
| [`iso/`](iso/) | Live ISO. An **overlay** on CachyOS-Live-ISO, not a fork. |
| [`pkgbuilds/pharos-repos`](pkgbuilds/pharos-repos/) | Repository order, signing and locks. |
| [`pkgbuilds/pharos-settings`](pkgbuilds/pharos-settings/) | COSMIC session defaults, via `/etc/skel`. |
| [`pkgbuilds/pharos-desktop`](pkgbuilds/pharos-desktop/) | The meta package. Install it and a CachyOS machine becomes Pharos. |
| [`pkgbuilds/apps/`](pkgbuilds/apps/) | The suite, packaged from git until it tags. |
| [`tools/`](tools/) | The generators and the audit. |

## Three things worth knowing before reading the code

**Repository order is the whole ballgame.** pacman takes each package from the
first repository in `pacman.conf` that carries the name and never looks lower —
a newer build underneath is simply not considered. Position *is* priority, and
it is the only lock pacman applies automatically. Pharos enables Chaotic-AUR,
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
# Live ISO
./iso/sync.sh
cd build/iso-src && sudo ./buildiso.sh -p pharos -v -w
# -> build/iso-src/out/pharos/

# A package
makepkg -sf -D pkgbuilds/pharos-settings

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

Scaffolded and verified as far as it can be without a build host. Verified by
running: the overlay applies cleanly to upstream at `4937780` and is
idempotent, the audit runs against a live 80-repository system and reports true
findings, all PKGBUILDs parse, and every COSMIC config format used here was
read off a running COSMIC 1.7.0 rather than assumed.

Not yet done, in the order it blocks things:

1. **`pharos-repo` does not exist.** The `[pharos]` repository is configured
   everywhere and served nowhere, so no ISO can build. Mirror `arch-repo`'s
   layout and reuse `linux-release-kit`'s `arch-repo.yml`. `packages.yml`
   builds the packages today and fails at the publish step, on purpose.
2. **No ISO has been built.** Everything upstream of `mkarchiso` is verified;
   `mkarchiso` itself has not run. Expect the first build to surface missing
   packages.
3. **Calamares is unbranded and untested under COSMIC.** `cachyos-calamares-next`
   is in the package list and will come up branded as CachyOS, if it comes up.
4. **Per-app dependencies are the libcosmic base set only.** namcap runs in CI
   and reports the rest; the additions have not been made.
5. **No keyring package.** `[pharos]` is `SigLevel = Required` against a key
   that has no `pharos-keyring` to distribute it.

## Licence

GPL-3.0-or-later, following CachyOS-Live-ISO, which `iso/` derives from.

COSMIC is a System76 trademark. Nothing here is named `cosmic-*`, and the
distribution does not claim to be a COSMIC product.
