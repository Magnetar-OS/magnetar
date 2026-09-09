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
3. **A repository placed above Arch re-sources the base system silently** —
   for every name it happens to share. How many names that is varies wildly by
   repository and is worth measuring rather than assuming; the table below has
   the numbers.

`SigLevel` and `Usage` are the other two controls, covered below.

## The order

```ini
# 1. CPU-optimised rebuilds of core/extra. Must outrank the repos they
#    rebuild or CachyOS's reason for existing is bypassed.
[cachyos-znver4] [cachyos-core-znver4] [cachyos-extra-znver4]

# 2. This distribution, packages and applications together.
[magnetar]

# 3. CachyOS proper: kernels, chwd, settings, gaming stack.
[cachyos]

# 4. Arch.
[core] [extra] [multilib]

# ---- everything below here can only supply names nothing above carries ----
# Ordered by who signs it, then by how much it overlaps Arch.
#
# 60 chaotic-aur    signed by a project, shadows 0
# 61 endeavouros    signed by a project, shadows 1
# 62 garuda         signed by a project, shadows 2
# 63 orhun          signed by an Arch developer, shadows 13
# 64 quarry         signed by an Arch developer, shadows 19
#
# 70 nemesis_repo   individually maintained, shadows 1
# 71 arch4edu       individually maintained, shadows 4
# 72 ownstuff       individually maintained, shadows 17
# 73 andontie-aur   individually maintained, shadows 23
# 74 Reborn-OS      shadows 30 — the most here, so last of the live repos
#
# 80 valve          locked: Usage = Sync Search, cannot install or upgrade
```

`*-testing` repositories are absent on purpose. CachyOS's v3/v4 repos already
track ahead of Arch stable; layering Arch testing on top of that produces a
system nobody can support, including us.

## Why each third party is here

All figures measured against `core` + `extra` + `multilib` (15,433 packages)
on 2026-09-09, not estimated:

| Repo | Packages | Shadows Arch | Signed by |
|---|---|---|---|
| `chaotic-aur` | 3167 | **0** | the Chaotic-AUR project |
| `endeavouros` | 56 | 1 | the EndeavourOS project |
| `garuda` | 102 | 2 | the Garuda project |
| `orhun` | 284 | 13 | Orhun Parmaksız, **Arch Linux developer** |
| `quarry` | 1685 | 19 | Anatol Pomozov, **Arch Linux developer** |
| `nemesis_repo` | 482 | 1 | Erik Dubois (ArcoLinux) |
| `arch4edu` | 1921 | 4 | Jingbei Li |
| `ownstuff` | 1396 | 17 | Marius Kittler (Martchus) |
| `andontie-aur` | 598 | 23 | Holly M. |
| `Reborn-OS` | 338 | 30 | the RebornOS project |

**Correcting an earlier version of this document.** It claimed Chaotic-AUR
"carries thousands of names that also exist in `extra`" and used that to argue
it must go last. The measurement says otherwise: Chaotic-AUR shadows **nothing**.
It builds AUR packages, and an AUR package is by definition not in the official
repositories. The reasoning was wrong, so the ordering changed with it —
Chaotic-AUR is now the *highest* of the third parties, because zero shadowing
is the strongest claim any of them can make.

The repository that genuinely does replace Arch wholesale is `extra-alucryd`:
265 of its 301 packages share a name with something Arch ships. It is not
configured here, and should not be.

**Every one of these repositories is signed.** Configurations that carry
`SigLevel = Never` for them — including the one this project was developed
against — are working around keys that were never imported, not around an
absence of signatures. Magnetar ships all ten at `SigLevel = Required` and
imports the key at enable time instead.

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

### Disabled by default (the bootstrap lock)

The third-party repositories ship **disabled**, and not as caution theatre. A
repository's keyring package lives *inside the repository it is needed to
verify*. That makes it impossible to express as a dependency: on a fresh
install, pacstrap cannot resolve `chaotic-keyring` because `[chaotic-aur]` is
not configured yet — and configuring it is exactly what the package declaring
that dependency does.

Building the first ISO is what surfaced this. `magnetar-repos` originally
hard-depended on all four third-party keyrings and mirrorlists, and pacstrap
refused the whole transaction:

```
:: unable to satisfy dependency 'chaotic-keyring' required by magnetar-repos
```

So enabling is an act, not a default:

```sh
magnetar-repo status
magnetar-repo enable chaotic-aur     # imports + lsigns the key, then the keyring
magnetar-repo enable endeavouros
magnetar-repo enable valve           # uncomments, stays Usage = Sync Search
magnetar-repo disable chaotic-aur
```

`enable` imports the project's signing key, locally signs it, and only then
installs the keyring — so the keyring package is signature-checked against the
key you just chose to trust, rather than downloaded and trusted blindly.

This costs nothing in ordering. A repository's position is fixed by the number
in its filename under `/etc/pacman.d/magnetar-repos.d/`, and every file there
sorts below the Arch repositories declared in `/etc/pacman.conf`. Enabling one
late cannot move it up.

Inside a drop-in the convention is: `# text` (hash-space) is prose, `#[repo]`
(hash immediately followed by content) is a disabled configuration line.
`magnetar-repo` toggles only the second kind, so the commentary explaining a
repository is never mistaken for configuration.

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

`magnetar-repos` owns the configuration. Everything below `[multilib]` ships
disabled; see "Disabled by default" above.

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
