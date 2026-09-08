# Package signing

`[magnetar]` is `SigLevel = Required DatabaseOptional`. Every package and the
database itself are signed, and an unsigned package in the repository is a
package nobody can install. That is the intended failure mode: the alternative,
`SigLevel = Optional TrustAll`, means unsigned packages from whoever answers the
DNS run install scripts as root.

## The key

```
382D 9848 41F8 C8A2 BFB9  5267 5623 FAF3 DF36 FFAF
Magnetar OS (package signing) <packages@magnetaros.com>
rsa4096, created 2026-09-08, expires 2031-09-07
```

One key, used directly for signing. Not a primary-plus-subkey arrangement: that
buys the ability to rotate the signing subkey without changing the fingerprint
users trust, which matters for a project with a key ceremony and an offline
primary. Magnetar has neither yet, and a structure nobody operates correctly is
worse than a simple one that is understood.

**It expires on 2031-09-07.** When it does, every installed machine starts
rejecting the repository. Extending it is one command and does not change the
fingerprint, so nothing downstream has to be reissued:

```sh
gpg --quick-set-expire 382D984841F8C8A2BFB952675623FAF3DF36FFAF 5y
# then re-export and ship a new magnetar-keyring
```

## How trust reaches a machine

1. `magnetar-keyring` ships `magnetar.gpg`, `magnetar-trusted` and
   `magnetar-revoked` to `/usr/share/pacman/keyrings/`.
2. Its install scriptlet runs `pacman-key --populate magnetar`, which imports
   the key and applies the ownertrust in `magnetar-trusted` (`:4:`, ultimate).
3. `magnetar-repos` depends on `magnetar-keyring`, so the key is in place
   before the repository it protects is ever reachable.

That dependency is the whole reason the keyring is a separate package. A
keyring served *from* the repository it verifies cannot be installed: pacman
refuses it for the same reason it refuses everything else there.

For the bootstrap case — a machine that has neither — the armoured key is at
`https://repo.magnetaros.com/magnetar.asc`. Check the fingerprint above before
running `pacman-key --lsign-key`.

## Signing a build

```sh
tools/sign-packages.sh          # signs anything unsigned, then repo-add -s -v
tools/sign-packages.sh --force  # re-sign everything
```

`repo-add -v` verifies each package's signature while indexing, so a bad
signature fails at publish time rather than on someone's machine.

The passphrase comes from `MAGNETAR_SIGNING_PASSPHRASE`, set locally by
`~/.config/magnetar/secrets.env` (mode 0600, deliberately outside any
git-tracked dotfiles directory).

## CI

Two repository secrets, and they must be two:

| Secret | Contents |
| --- | --- |
| `MAGNETAR_SIGNING_KEY` | `~/.config/magnetar/key-backup/magnetar-secret.asc` |
| `MAGNETAR_SIGNING_PASSPHRASE` | the passphrase |

The exported key is passphrase-encrypted, so neither secret is useful alone.
Splitting them is the only benefit a passphrase gives a key that a machine has
to use unattended — take it.

```yaml
- name: Import the signing key
  run: |
    printf '%s' "${{ secrets.MAGNETAR_SIGNING_KEY }}" | gpg --batch --import
    printf '%s' "${{ secrets.MAGNETAR_SIGNING_PASSPHRASE }}" > /tmp/pp
- name: Sign
  env:
    MAGNETAR_SIGNING_PASSPHRASE: ${{ secrets.MAGNETAR_SIGNING_PASSPHRASE }}
  run: tools/sign-packages.sh
```

## Backups

`~/.config/magnetar/key-backup/` (mode 0700) holds:

| File | What it is |
| --- | --- |
| `magnetar-secret.asc` | the private key, passphrase-encrypted |
| `382D...FFAF.rev` | the revocation certificate |
| `magnetar.asc` | the public key |

**Get the revocation certificate off this machine.** It is the only way to tell
the world the key is dead if the private key is lost or stolen, and it is
useless to you if it was only ever stored next to the key it revokes. It needs
no passphrase to use, which cuts both ways: anyone holding it can revoke the
key, so it wants somewhere private, not somewhere public.

The same goes for `magnetar-secret.asc`. If this disk dies with no copy
elsewhere, the key is gone: every installed machine keeps trusting a
fingerprint nothing can sign for any more, and the only route out is shipping a
new keyring through a repository nobody can install from.

## Revoking

If the key is compromised:

1. `gpg --import ~/.config/magnetar/key-backup/382D...FFAF.rev`
2. Publish the revoked public key to `https://repo.magnetaros.com/magnetar.asc`
3. Add the fingerprint to `magnetar-revoked` in `magnetar-keyring`, add the new
   key to `magnetar.gpg` and `magnetar-trusted`, bump `pkgver`, ship it
4. Re-sign every package in the repository with the new key

Step 3 is why `magnetar-revoked` exists as an empty file today rather than
being added when first needed: the mechanism should already be in place and
understood before the day someone has to use it in a hurry.
