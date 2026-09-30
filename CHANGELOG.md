# Changelog

User-facing changes to the Magnetar distribution: the ISO, the installer, the
distribution packages (`magnetar-*`, `cutecosmic`) and the repository
configuration. The applications keep their own changelogs.

## [Unreleased]

### Added

- An installed system has Bluetooth, a firewall, a full font set and audio
  firmware. Magnetar's installer list replaced CachyOS's entirely and left out
  what CachyOS's common group brought, so an install had no `bluez`, no `ufw`,
  only the fonts COSMIC depends on, and no `sof-firmware` or `alsa-firmware`
  for laptops whose sound needs them. A hidden "Magnetar system" group now
  installs CachyOS's Bluetooth, firewall and font selections and the audio
  firmware. The installer's existing steps then enable `bluetooth.service` and
  turn `ufw` on, denying incoming and allowing outgoing connections.

### Changed

- `[magnetar]` no longer keeps a renamed package's old name. When a package
  there is replaced by another one (`replaces=`), publishing removes the old
  name from the database and the repository, in both architectures. The old
  name otherwise stayed installable for good, and kept colliding with the
  other repository that made the rename necessary.
- The artwork the distribution ships — the wallpapers and ASCII logo in
  `magnetar-settings`, the logo in `magnetar-branding`, the installer's images
  in `magnetar-calamares`, the ISO's boot splashes — is licensed CC-BY-SA-4.0,
  and those packages declare it beside GPL-3.0-or-later.
- The canonical `/usr/share/magnetar/pacman.conf` no longer enables the
  CachyOS znver4 repositories for every machine: all three optimised sets
  (znver4, v4, v3) ship commented out, and the new `magnetar-pacman-conf`
  renders the file with the set this CPU can run, using CachyOS's own
  detection. Adopting the old file on a CPU without AVX-512 installed
  packages that crash with SIGILL.

### Fixed

- Installing `magnetar-branding` on a CachyOS machine that boots with limine no
  longer cuts limine's tools off from their boot entries. `limine-entry-tool`
  and `limine-snapper-sync` find their group in `limine.conf` by the OS name,
  CachyOS's installer names it `CachyOS`, and the package renames the OS: new
  kernels went into a second group and snapshot entries stopped, with no
  error. The package now sets `TARGET_OS_NAME="CachyOS"` in
  `/etc/default/limine` when that is the group the machine boots from and
  nothing else is set; `limine.conf` itself is not touched. Machines that
  already ran into this are repaired by the upgrade, unless limine's tools
  have started a Magnetar group of their own, which is then left in use.
- A fresh install with limine has one boot-entry group, named Magnetar.
  CachyOS's installer writes the group as `CachyOS` whatever the system is
  called, so an install ended up with an empty CachyOS group and a second one
  limine's tools created; the installer now names the group before it is
  filled.
- `magnetar-repo-audit` is clean on a correct machine at every CPU level. Its
  list of what CachyOS deliberately takes over from Arch was recorded on one
  Zen 4 machine, where the znver4 repositories carry everything; on an
  x86-64-v3 or -v4 machine, where `mesa` comes from `[cachyos]` itself, it
  reported 33 violations, and 54 on a baseline CPU. The list now covers all
  four.
- The installer installs Magnetar. Calamares read CachyOS's package list
  (fetched from CachyOS's GitHub, falling back to CachyOS's own file) instead
  of Magnetar's, so an install got no COSMIC, no `magnetar-*` packages and no
  suite; it now reads only Magnetar's list.
- The installed system's `/etc/pacman.conf` carries `[magnetar]`, between the
  CPU's optimised CachyOS repositories and `[cachyos]`, with the Magnetar key
  trusted. The installer used CachyOS's file, which has no `[magnetar]`, so
  the Magnetar packages could not be found during the install and would never
  have been updated after it. The installed file is the canonical one,
  rendered for the machine's CPU by `magnetar-pacman-conf`.

- A CI-built ISO carries the distribution packages of the commit it was built
  from. The ISO workflow used to start on the same push as the workflow that
  publishes those packages and could finish first, shipping the previous
  installer; it now runs after a successful publish and waits until
  `[magnetar]` serves the new versions.

- `magnetar-settings` lists `fastfetch` and `cutecosmic` as optional
  dependencies again; a later `optdepends=` reassignment had dropped them.
- `magnetar-repo enable arch4edu` works on a machine that does not have
  `arch4edu-keyring` yet. It used to demand that package, which only exists
  inside the repository being enabled, and exit before enabling it.
- The `IgnorePkg` example in `/etc/pacman.d/magnetar-repos.d/99-local.conf`
  carries an `[options]` header. Without it pacman read the line as part of
  the last repository section and ignored it with a warning.
- The canonical `/usr/share/magnetar/pacman.conf` no longer sets `HoldDir`,
  which is not a pacman option; every pacman command on a machine that
  adopted the file printed a warning about it.
- `magnetar-repo-audit` recognises ALHP by its real repository names
  (`[core-x86-64-v3]` and so on) and the CachyOS v4 set, so ALHP enabled
  alongside CachyOS's optimised repositories fails the audit as documented.
- `magnetar-desktop` installs on x86-64-v3 and -v4 machines. `cutecosmic`
  required exactly `qt6-base=6.11.2-3`, which CachyOS's optimised repositories
  replace with their `6.11.2-3.1` rebuild, so nothing could satisfy it there.
  The pin now accepts sub-rebuilds of the same Qt build and still refuses any
  other.
- `magnetar-desktop` lists Pencil and Pocket among its optional dependencies,
  with the other seven suite apps.
- An installed system shows the Magnetar logo wherever `os-release`'s
  `LOGO=magnetar` is read (COSMIC Settings' About page, fastfetch): the icon
  moved from the installer package, which an installed system does not have,
  to `magnetar-branding`. The live ISO's `os-release` uses Magnetar's colour,
  as the installed one does.
