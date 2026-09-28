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
