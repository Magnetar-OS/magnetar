# Changelog

User-facing changes to the Magnetar distribution: the ISO, the installer, the
distribution packages (`magnetar-*`, `cutecosmic`) and the repository
configuration. The applications keep their own changelogs.

## [Unreleased]

### Fixed

- `magnetar-settings` lists `fastfetch` and `cutecosmic` as optional
  dependencies again; a later `optdepends=` reassignment had dropped them.
- `magnetar-repo enable arch4edu` works on a machine that does not have
  `arch4edu-keyring` yet. It used to demand that package, which only exists
  inside the repository being enabled, and exit before enabling it.
