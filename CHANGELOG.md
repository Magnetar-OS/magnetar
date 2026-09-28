# Changelog

User-facing changes to the Magnetar distribution: the ISO, the installer, the
distribution packages (`magnetar-*`, `cutecosmic`) and the repository
configuration. The applications keep their own changelogs.

## [Unreleased]

### Fixed

- `magnetar-settings` lists `fastfetch` and `cutecosmic` as optional
  dependencies again; a later `optdepends=` reassignment had dropped them.
