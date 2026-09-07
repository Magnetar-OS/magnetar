# Repository order and locking

Magnetar enables more third-party pacman repositories than stock Arch. That is a
deliberate feature and the single most likely way to break the system, so the
order and the locks are policy, not preference.

## How pacman actually resolves this

The mechanism people expect (`pacman picks the highest version anywhere`) is not
what happens, and the difference is the whole basis of this document.

For each package, `pacman -Syu` walks the repositories **in the order they
appear in `pacman.conf`** and stops at the first one whose database contains
that package name. Only that repository's version is compared against what is
installed. A newer build sitting in a lower repository is never considered.

Three consequences:

1. **Order is a hard priority.** Position in the file *is* the lock. Nothing
   else in pacman expresses "prefer this repo for this package".
2. **A high repository shadows every lower one** for every package name it
   carries — including names it carries only incidentally.
3. **Adding a large repository high in the file silently re-sources the base
   system.** Chaotic-AUR alone carries thousands of names that also exist in
   `extra`. Placed above `extra`, it becomes the source of truth for all of
   them, from someone else's build farm, with no announcement.

`SigLevel` and `Usage` are the other two controls, covered below.

## The order

```ini
# 1. CPU-optimised rebuilds of core/extra. Must outrank the repos they rebuild
#    or CachyOS's entire reason for existing is bypassed.
[cachyos-znver4]
[cachyos-core-znver4]
[cachyos-extra-znver4]

# 2. This distribution. Above [cachyos] so a Magnetar package can deliberately
#    replace a CachyOS one (magnetar-settings over cachyos-settings, say).
#    Below the v3/v4 repos so it can never shadow an optimised rebuild.
#    Every package here is named magnetar-*, so incidental shadowing is
#    structurally impossible; tools/repo-audit.sh proves it each build.
[magnetar]

# 3. CachyOS proper: kernels, chwd, settings, gaming stack.
[cachyos]

# 4. Released entro314labs applications. Below [cachyos] because it holds
#    ordinary desktop apps, not system components, and should never win a
#    name collision against a system package.
[entro314labs]

# 5. Arch.
[core]
[extra]
[multilib]

# 6. Small, narrow-purpose third parties. Below Arch: they may only supply
#    names Arch does not have.
[endeavouros]

# 7. Large, broad third parties. Last, so they can supply only what nothing
#    above carries.
[chaotic-aur]

# 8. Locked repositories. Present, synced, searchable, and unable to install
#    or upgrade anything. See "Locks".
[jupiter]
[holo]
```

`*-testing` repositories are absent on purpose. CachyOS's v3/v4 repos already
track ahead of Arch stable; layering Arch testing on top of that produces a
system nobody can support, including us.

## Why each third party is here

| Repo | What it is for | Risk | Placement |
|---|---|---|---|
| `endeavouros` | The `eos-*` tools — `eos-update`, `welcome`, rankmirrors, a handful of small utilities. About 40 packages, nearly all uniquely named. | Low. Narrow, well-maintained, signed. | Below Arch. It only ever supplies `eos-*`. |
| `chaotic-aur` | Prebuilt AUR. Removes the "compile for 40 minutes" step for the long tail. | **High.** Thousands of packages, many shadowing `extra`. Built by a third party on their schedule. | Dead last among live repos. |
| `jupiter` / `holo` (Valve) | SteamOS's own packages: `jupiter-hw-support`, `steamdeck-dsp`, Deck firmware and hardware quirks. | **High and structural.** These target SteamOS's *frozen* Arch snapshot, not rolling Arch. Names like `mesa` and `gamescope` exist there at versions pinned to a distribution we are not. | Locked (below). Off by default. |

**Be honest about Valve's repos before enabling them.** Most of what people
want from them, Magnetar already has from CachyOS: `proton-cachyos`,
`gamescope-session`, `wine-cachyos`, the gaming meta package, and a kernel
tuned harder than Valve's. What is genuinely Deck-only is hardware enablement
for hardware you are not running. Enable them if you are targeting Deck
hardware specifically; otherwise the risk buys nothing.

## Locks

### Order (primary)
Covered above. It is the only lock that acts on every package automatically.

### `Usage` (for repos that must not act)
```ini
[jupiter]
Usage = Sync Search
Server = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch
```
`Usage = Sync Search` lets the database sync and `pacman -Ss` find things, while
withholding `Install` and `Upgrade`. The repository is a catalogue you can read,
not a source packages can arrive from. Pulling something from it is then an
explicit, auditable act: temporarily add `Install`, take the package, remove it
again — and accept that it will never be upgraded while the lock is on.

Do not "solve" that staleness by granting `Upgrade`. A repo pinned to a frozen
Arch snapshot upgrading packages on a rolling system is the failure mode this
lock exists to prevent.

### `SigLevel` (trust)
Every third-party repository is `SigLevel = Required DatabaseOptional` and ships
its own keyring package. **No repository in Magnetar uses `TrustAll`.**

`SigLevel = Optional TrustAll` — which appears in a lot of copy-pasted
instructions, including the current `arch-repo` README's quick-start — means
unsigned packages from that host execute install scripts as root, unverified.
That is acceptable for a personal repo you are testing; it is not acceptable in
a distribution's default `pacman.conf`, where the user did not choose the host.

Keyrings are installed as dependencies of `magnetar-repos`, so the trust path
exists before the repository is ever reachable.

### `HoldPkg` (removal guard)
```ini
HoldPkg = pacman glibc systemd base linux-cachyos magnetar-repos magnetar-keyring
```
Not a version pin — pacman has no version pinning. It forces a confirmation
prompt before removing anything that would leave the machine unbootable or
unable to install packages, `magnetar-repos` included: dropping it silently
removes the repository configuration that everything else depends on.

### `IgnorePkg` (targeted, temporary)
Empty by default and it should stay that way. An `IgnorePkg` entry is a
partial upgrade waiting to happen — on a rolling release it breaks the machine
eventually, not immediately. If one is ever needed, it belongs in
`/etc/pacman.d/magnetar-repos.d/99-local.conf` with a comment saying who added
it, why, and what condition retires it.

### Forbidden combinations

- **ALHP with the CachyOS v3/v4 repos.** Both ship `-x86-64-v3`/`v4` rebuilds of
  `core` and `extra`. Enabled together, order decides which rebuild you get per
  package and you end up with a base system split across two build farms with
  different toolchains. Pick one. Magnetar picks CachyOS.
- **Arch `*-testing` above the CachyOS repos.** Defeats the optimised rebuilds
  and mixes two release cadences.
- **Any AUR-derived repository above `extra`.** Includes `chaotic-aur`,
  `garuda`, `arcanisrepo`, `archlinuxcn`. They are allowed to fill gaps, never
  to replace the base system.

## Layout on disk

`magnetar-repos` owns the configuration:

```
/etc/pacman.conf                        the ordered file, sections 1-5
/etc/pacman.d/magnetar-repos.d/60-endeavouros.conf
/etc/pacman.d/magnetar-repos.d/70-chaotic-aur.conf
/etc/pacman.d/magnetar-repos.d/80-valve.conf      (locked, Usage = Sync Search)
/etc/pacman.d/magnetar-repos.d/99-local.conf      (yours, never packaged)
/usr/share/magnetar/pacman.conf                   the canonical reference copy
```

`pacman.conf` ends with `Include = /etc/pacman.d/magnetar-repos.d/*.conf`. The
glob expands in filename order, which is why the files are numbered: the number
*is* the priority, and every one of them sorts below the Arch repositories
declared inline above the `Include`. A drop-in cannot accidentally outrank
`core` because there is nowhere in that directory for it to go.

`99-local.conf` is yours. It is listed in the package as a backup file so
upgrades never touch it.

## Verifying it

`tools/repo-audit.sh` reads the configured databases and reports, for every
package name carried by more than one enabled repository, which repository wins.

A name's *natural home* is the first of `core`/`extra`/`multilib` that carries
it — where pacman would take it from if nothing above interfered. The audit
fails when:

- **a repository ordered above that home wins the name**, and the pair is not
  declared in `tools/repo-overrides.txt`. This is the only shadowing that can
  happen: a repository *below* Arch can never win, which is why placement below
  `extra` is itself the guard for `endeavouros` and `chaotic-aur`.
- **any enabled repository resolves to `TrustAll` or `Never`.**
- **ALHP and the CachyOS optimised repos are both enabled.**

It also warns when a package exists only in a locked repository and is
nevertheless installed — meaning something arrived while the lock was off.

The override list is empirical, not documentary. It was produced by running the
audit against a live CachyOS install and recording what CachyOS actually
overrides; CachyOS does not publish that set. Two packages assumed to be on it
(`mesa`, notably) turned out not to be. Regenerate it after a CachyOS repo
change rather than reasoning about it:

```sh
tools/repo-audit.sh | awk '$1=="FAIL" && $4=="cachyos" {print "cachyos:"$2}'
```

It runs in CI on every change to the repo configuration and before every ISO
build, so shadowing is caught at build time rather than on someone's machine
three weeks later.
