# Online accounts

How Google and Microsoft accounts sign in on Magnetar, and what Magnetar has to
register before its own sign-in can replace the stopgap.

## Today: GNOME Online Accounts

The suite's own browser sign-in (`cosmic-pim-auth`) is complete, but it needs
an OAuth client id, which is a registration held with Google and with
Microsoft. Until Magnetar has its own, Google and Microsoft accounts are added
through GNOME Online Accounts, which signs in under GNOME's registration:

- `gnome-online-accounts` and `gnome-online-accounts-gtk` are on the ISO and in
  the installer's hidden system group.
- Accounts (`magnetar-accounts`) offers "Sign in with Online Accounts" for a
  Google or Microsoft address, opens GOA's window, and links what GOA holds
  into the suite's account list when it closes. `magnetar-accounts adopt`
  does the same from a shell.
- Tokens stay GOA's. The suite asks GOA for a fresh access token when the one
  it has expires; the refresh token never leaves GOA.

Without GOA and without a client id, Gmail can still be added with an app
password (mail only), and Outlook.com cannot be added at all — Microsoft takes
no password for it.

## Later: Magnetar's own registrations

What this needs, in order. None of it is code.

### Google

1. A Google Cloud project owned by the Magnetar-OS organisation.
2. OAuth consent screen: external, app name "Magnetar", support address,
   homepage and privacy policy on `magnetaros.com` (the domain must be
   verified in Search Console).
3. An OAuth client of type **Desktop app**. Its client id and client secret
   are not secret in a desktop application — PKCE protects the flow — and are
   shipped in a package.
4. Scopes, as `cosmic-pim-accounts/providers/google.toml` requests them:
   `openid`, `email`, `profile`, `calendar`, `carddav`, `gmail.modify`,
   `https://mail.google.com/`. The two Gmail scopes are **restricted**.
5. Restricted-scope verification. Until it passes, sign-in shows an
   "unverified app" warning and at most 100 users can grant access. Google's
   stated security assessment applies to apps that reach user data from or
   through a server; a desktop client that talks to Gmail directly from the
   user's machine should fall outside it, but Google decides that in review.

### Microsoft

1. An app registration in Microsoft Entra ID, supported account types
   "accounts in any organizational directory and personal Microsoft accounts".
2. Platform "Mobile and desktop applications", redirect URI
   `http://127.0.0.1:49174/callback` (the port in `microsoft.toml`), and
   "Allow public client flows" on. No client secret.
3. Delegated permissions, as `microsoft.toml` requests them: `offline_access`,
   `Mail.ReadWrite`, `Mail.Send`, `IMAP.AccessAsUser.All`, `SMTP.Send`, plus
   `openid`, `email`, `profile`.
4. Publisher verification (a Microsoft AI Cloud Partner Program account),
   without which work and school tenants show the app as unverified and may
   refuse user consent.

### Shipping them

A package — `magnetar-online-accounts` or a file in `magnetar-settings` —
installs two manifests that name only the ids; everything else comes from the
built-in manifests:

```toml
# /usr/share/cosmic-pim/providers/google.toml
id = "google"
[oauth]
client_id = "….apps.googleusercontent.com"
client_secret = "…"
```

```toml
# /usr/share/cosmic-pim/providers/microsoft.toml
id = "microsoft"
[oauth]
client_id = "00000000-0000-0000-0000-000000000000"
```

With those installed, Accounts puts "Continue in the browser" first for
Google and Microsoft addresses, Online Accounts second, and the app password
last.
