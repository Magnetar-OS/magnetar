#!/usr/bin/env python3
"""Generate the Magnetar ISO package list from CachyOS's Plasma one.

CachyOS maintains packages_desktop.x86_64 actively — hardware enablement,
filesystem tools, firmware. Forking that list by hand means silently falling
behind it, and the symptom is an ISO that stops booting on somebody's laptop.

So the list is derived: take theirs, drop the Plasma session, add COSMIC.
Re-run after bumping UPSTREAM_ISO_REF in branding.env.

    tools/gen-iso-packages.py <path to upstream packages_desktop.x86_64>
"""
import sys
from pathlib import Path

# Everything CachyOS's Plasma edition pulls that a COSMIC edition must not.
# alacritty goes too: ghostty is the terminal Magnetar ships.
DROP = {
    'bluedevil', 'breeze-gtk', 'dolphin', 'kate', 'kcalc', 'kde-gtk-config',
    'kinfocenter', 'konsole', 'kscreen', 'kxkb2locale1', 'partitionmanager',
    'plasma-desktop', 'plasma-integration', 'plasma-nm', 'plasma-pa',
    'plasma-thunderbolt', 'plasma-workspace', 'polkit-kde-agent', 'spectacle',
    'plasma-login-manager', 'cachyos-kde-settings', 'alacritty',
    # CachyOS's welcome app. It is CachyOS-branded and its install button runs
    # CachyOS's installer, so on a Magnetar ISO it advertises and installs the
    # wrong distribution. The installer is reachable from the app library as
    # "Install Magnetar" (magnetar-calamares).
    'cachyos-hello',
    # Provides /usr/bin/cachyos-installer, "New CLI installer for CachyOS".
    # A Magnetar ISO carrying a second installer that produces a different
    # distribution is not a feature; someone would eventually run it and get a
    # CachyOS install from a Magnetar disc.
    'cachyos-cli-installer-new',
}

COSMIC = """# --- COSMIC ---------------------------------------------------------------
cosmic-session
cosmic-comp
cosmic-panel
cosmic-applets
cosmic-app-library
cosmic-bg
cosmic-files
cosmic-greeter
cosmic-icon-theme
cosmic-idle
cosmic-initial-setup
cosmic-launcher
cosmic-notifications
cosmic-osd
cosmic-player
cosmic-randr
cosmic-screenshot
cosmic-settings
cosmic-settings-daemon
cosmic-sound-theme
cosmic-store
cosmic-terminal
cosmic-text-editor
cosmic-wallpapers
cosmic-workspaces
xdg-desktop-portal-cosmic
greetd

# --- Portal stack ----------------------------------------------------------
# xdg-desktop-portal-cosmic is a backend. Without the frontend and the GTK
# fallback, file pickers in GTK and Electron applications fail outright.
xdg-desktop-portal
xdg-desktop-portal-gtk

# --- Magnetar ----------------------------------------------------------------
magnetar-keyring
magnetar-repos
magnetar-settings
magnetar-desktop
magnetar-calamares
ghostty

# --- Adopted from the Pop!_OS survey ---------------------------------------
# See docs/POP-OS-ADOPTION.md for why these three and not the rest.
#
# cutecosmic: Qt platform theme for COSMIC. Calamares is Qt and is the first
# thing anyone sees; without this it renders as a generic Qt application on a
# COSMIC desktop and the installer branding is wasted.
cutecosmic
# popsicle: System76's USB flasher. We produce a 3.1 GB ISO and shipped nothing
# to write it with.
popsicle
# fwupd: firmware updates. Pop ships firmware-manager; this is the cross-distro
# equivalent and we had no firmware update path at all.
fwupd

# --- The suite -------------------------------------------------------------
# -git builds served from [magnetar]. They ship on the live ISO rather than
# sitting in optdepends: the suite is what the distribution is for, and an
# ISO that does not show it is an ISO nobody can evaluate.
jump-git
peek-git
grabit-git
locket-git
envelope-git
circle-git
slate-git
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    upstream = Path(sys.argv[1])
    if not upstream.is_file():
        print(f"gen-iso-packages: {upstream} not found. Run iso/sync.sh first.",
              file=sys.stderr)
        return 2

    pkgs = upstream.read_text().split()
    kept = [p for p in pkgs if p not in DROP]
    removed = sorted(DROP & set(pkgs))
    stale = sorted(DROP - set(pkgs))

    header = (
        "# Magnetar live ISO package list.\n"
        "#\n"
        "# GENERATED from CachyOS-Live-ISO's packages_desktop.x86_64 by\n"
        "# tools/gen-iso-packages.py, with the Plasma session removed and COSMIC in\n"
        "# its place. Regenerate after bumping UPSTREAM_ISO_REF rather than editing\n"
        "# by hand: CachyOS adds hardware, filesystem and firmware packages to that\n"
        "# list regularly, and losing one silently is how an ISO stops booting on\n"
        "# somebody's machine.\n"
        "#\n"
        f"# Dropped from upstream ({len(removed)}): {' '.join(removed)}\n"
        "#\n\n"
    )

    out = Path(__file__).parent.parent / "iso/overlay/archiso/packages_magnetar.x86_64"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(header + "\n".join(kept) + "\n\n" + COSMIC)

    print(f"kept from upstream : {len(kept)}")
    print(f"dropped            : {len(removed)}")
    if stale:
        print(f"WARNING: in DROP but not in upstream any more: {' '.join(stale)}")
        print("         Upstream removed these. Prune DROP so it keeps meaning something.")
    print(f"written            : {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
