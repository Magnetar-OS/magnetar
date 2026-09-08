# What to take from Pop!_OS

Magnetar is often described as "a bespoke Pop!_OS on a CachyOS base". That is
close to true already, and it is worth being precise about why: **COSMIC is the
Pop!_OS experience.** The desktop, the launcher, the tiling, the settings, the
applets — that is what people mean when they say they like Pop, and Magnetar
ships all of it from the same upstream System76 writes.

So the question is not "how do we become like Pop". It is "what is left in
Pop!_OS once COSMIC is removed, and is any of it worth having on Arch".

Surveying all 200 repositories in the `pop-os` organisation, the answer sorts
into four piles, and three of them are empty for us.

## 1. Debian plumbing — not applicable

Roughly 60% of `pop-os` is Debian/Ubuntu packaging: forks of firefox,
thunderbird, mesa, libdrm, xwayland, pipewire, systemd, flatpak, zfs-linux,
console-setup, the NVIDIA driver packaging, `repo-*`, `buildchain`,
`apt.pop-os.org`. These exist because Pop is a Debian derivative and has to
carry its own builds. On Arch every one of them is answered by a package that
already exists.

Same for `kernelstub` (we boot with limine), `distinst` and `installer` (we use
Calamares), and `pop-upgrade` (release upgrades are meaningless on a rolling
distribution).

## 2. System76 hardware — not applicable

`system76-driver`, `system76-dkms`, `system76-acpi-dkms`, `system76-firmware`,
`system76-oled`. These drive System76 laptops: their EC, their keyboard
backlight, their firmware updater. On other hardware they do nothing. Ship them
only if Magnetar ever targets a System76 machine specifically.

## 3. Already covered, better, by CachyOS

This is the pile worth being careful about, because these look like obvious wins
and are not.

### system76-scheduler — **skip**, and the reason is specific

Its headline feature is foreground boosting: the focused window and its children
get more CPU. That is a genuinely good idea, and it is why people rate it.

It works by the *compositor* calling `SetForegroundProcess(u32)` on
`com.system76.Scheduler` over D-Bus. Pop's own README is explicit that this
happens "when combined with pop-shell".

**cosmic-comp does not make that call.** Neither does cosmic-session, nor
cosmic-settings-daemon:

```sh
$ strings /usr/bin/cosmic-comp | grep -E 'com\.system76\.Scheduler|SetForegroundProcess'
$   # nothing, in all three binaries
```

Without it, system76-scheduler degrades to rule-based process priorities keyed
on process names — which is exactly what `ananicy-cpp` does, and CachyOS ships
`cachyos-ananicy-rules` with a far larger rule set tuned for this base.

It is also not a free addition. `cachyos-settings` **depends** on `ananicy-cpp`
and `cachyos-ananicy-rules`, and `magnetar-desktop` depends on
`cachyos-settings`, so ananicy is running on every Magnetar install. Adding
system76-scheduler means two daemons rewriting each other's nice values —
neither package declares a conflict, so pacman will let you do it, and the
result is silently worse than either alone.

Revisit if cosmic-comp gains the D-Bus call. Until then this is a downgrade
wearing the costume of an upgrade.

### system76-power — **skip**

`Provides: power-profiles-daemon`, so it is a replacement rather than an
addition. Its distinctive feature is hybrid-graphics switching on System76
machines. CachyOS uses `power-profiles-daemon` plus `chwd` for graphics
detection, both already on the ISO. Diverging from the base's power stack to
gain a feature aimed at hardware we are not targeting is not a trade worth
making.

### pop-launcher — **already shipped**

It is in `cachyos-extra-znver4` and on the ISO, because `jump` uses it as its
search engine. Pop's launcher service is already the thing answering queries.

## 4. Worth adopting

### cutecosmic — the clearest win

A Qt platform theme for COSMIC, relaying dark mode, colours and fonts from
COSMIC settings into Qt applications. Not from System76 — it is an independent
project (`IgKh/cutecosmic`), packaged in the AUR as `cutecosmic-git`.

This is not theoretical. **Calamares is Qt**, it is on our ISO, and in the VM
test it rendered as a generic Qt application against a COSMIC desktop. So do
`cachyos-kernel-manager` and `cachyos-packageinstaller` if we ever ship them.
We spent real effort on installer branding; a platform theme is the other half
of making it not look borrowed.

Cost: package `cutecosmic-git` into `[magnetar]`, add to `magnetar-desktop`.
It is marked experimental upstream, so it wants testing before it goes in the
default install rather than after.

### popsicle — obvious, cheap

System76's USB flasher, GTK/Rust, already in the `cachyos` repository. We
produce a 3.1 GB ISO and currently ship nothing to write it to a USB stick.
A distribution that cannot flash its own installer is an odd thing.

### fwupd — a real gap

Pop ships `firmware-manager` for firmware updates. The cross-distro equivalent
is `fwupd`, in `cachyos-extra-znver4`, and **not currently on our ISO**. Laptop
firmware and SSD updates are a genuine user-facing capability we are simply
missing. Add it.

### inputplumber — conditional

Input device management for gamepads and handhelds; Pop packages it, and it is
in `cachyos-extra-znver4`. Worth it only if Magnetar targets handhelds. CachyOS
already has handheld support, so this is a decision about scope, not a gap.

### pop-icon-theme — probably not

In `extra`, so trivially available. But Magnetar shipping Pop's icons is the
one place where "bespoke Pop!_OS" stops being a compliment. `cosmic-icon-theme`
is already on the ISO and is the neutral choice.

## 5. Ideas worth stealing, rather than packages

These are capabilities Pop has that Magnetar lacks, where the value is the idea
and the implementation would be ours.

**Refresh Install.** Pop's installer can reinstall the system while preserving
`/home` and user accounts. Calamares has no equivalent. For a rolling distro
that people will eventually break, this is the difference between "reinstall and
lose everything" and "reinstall and carry on". It is the single most valuable
thing on this page and the most work.

**Recovery partition.** Pop ships one, so a machine that will not boot can still
repair itself without external media. CachyOS's answer is snapper snapshots,
which we inherit — a different trade: snapshots handle a bad upgrade well and a
dead ESP or unbootable kernel badly.

**A settings panel of our own.** `support-panel` is a COSMIC Settings page with
system information and support links. Magnetar has a suite of libcosmic
applications already; a `magnetar-settings-panel` showing the ISO version, the
repository state and the output of `magnetar-repo-audit` would fit both the
desktop and the skills already in this project.

**A maintenance dashboard.** `poparazzi` is Pop's. The Magnetar equivalent
would surface pending updates, orphaned packages, failed units, snapshot state
and third-party repository status in one place — most of which we already
compute in `tools/`.

## 6. Code, not packages

Pop publishes Rust crates that are useful to the *applications*, independent of
the distribution: `freedesktop-icons`, `freedesktop-desktop-entry`,
`recently-used-xbel`, `dbus-settings-bindings`, `window_clipboard`,
`softbuffer`, `glyphon`.

`jump`, `peek`, `circle`, `slate` and `envelope` are libcosmic applications
already, so they are downstream of Pop's platform work whether or not anyone
calls it adoption. These crates are the layer below that, and reaching for them
beats reimplementing desktop-entry parsing or icon lookup by hand.

## Summary

| Item | Verdict |
| --- | --- |
| cutecosmic | **Adopt** — Qt apps, Calamares included, look unthemed without it |
| popsicle | **Adopt** — we ship an ISO and nothing to flash it with |
| fwupd | **Adopt** — firmware updates are missing outright |
| inputplumber | Conditional on targeting handhelds |
| pop-icon-theme | Skip — this is where borrowed identity shows |
| system76-scheduler | **Skip** — foreground boosting does not work on cosmic-comp, and it fights ananicy |
| system76-power | **Skip** — replaces the base's power stack for a System76-only feature |
| system76-{driver,dkms,acpi,firmware,oled} | Skip — System76 hardware only |
| kernelstub, distinst, pop-upgrade | Skip — limine, Calamares, rolling |
| Debian packaging forks | Not applicable |
| Refresh Install | **Build** — the biggest real gap |
| Recovery partition | Consider against snapper |
| Settings panel, maintenance dashboard | Build, if the suite wants more surface |
