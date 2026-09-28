# Changelog

User-facing changes to the Magnetar distribution: the ISO, the installer, the
distribution packages (`magnetar-*`, `cutecosmic`) and the repository
configuration. The applications keep their own changelogs.

## [Unreleased]

### Changed

- The canonical `/usr/share/magnetar/pacman.conf` no longer enables the
  CachyOS znver4 repositories for every machine: all three optimised sets
  (znver4, v4, v3) ship commented out, and the new `magnetar-pacman-conf`
  renders the file with the set this CPU can run, using CachyOS's own
  detection. Adopting the old file on a CPU without AVX-512 installed
  packages that crash with SIGILL.

### Fixed

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
