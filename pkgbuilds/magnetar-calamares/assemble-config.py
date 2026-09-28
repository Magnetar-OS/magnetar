#!/usr/bin/env python3
"""Patch CachyOS's Calamares configuration, copied into CONFDIR, into Magnetar's.

Usage: assemble-config.py CONFDIR

magnetar-install copies /etc/calamares and settings_online.conf into CONFDIR
and lays Magnetar's module files over them; this changes the lines that must
differ. Every patch asserts on the exact text it expects, and the whole run
fails naming each one that CachyOS has moved, before anything is written.

1. settings.conf: branding -> magnetar.
2. settings.conf: drop the desktop packagechooser step. Magnetar installs
   COSMIC; a step offering Plasma or GNOME instead would install a system this
   project does not build, test or support.
3. netinstall.conf: read only CONFDIR/modules/netinstall.yaml. CachyOS's
   groupsUrl fetches its own list from GitHub first and falls back to
   /etc/calamares/modules/netinstall.yaml; neither is Magnetar's, so without
   this the install gets CachyOS's groups and none of Magnetar's packages.
4. shellprocess-before-online.conf: write the target's /etc/pacman.conf with
   magnetar-pacman-conf instead of copying /etc/pacman-more.conf and running
   detect-architecture. The result is the canonical Magnetar file — this CPU's
   optimised set, then [magnetar], then [cachyos] — so pacstrap and the
   package step can resolve magnetar-* and the suite. It is written without
   the magnetar-repos.d drop-in Include, which pacman rejects while that
   directory does not exist yet.
5. shellprocess.conf (runs in the target after the packages are installed):
   rewrite /etc/pacman.conf with the target's own magnetar-pacman-conf, now
   with the drop-in Include, so the installed system carries exactly the
   canonical file.
"""
import pathlib
import re
import sys

PACMAN_CONF_TOOL = "/usr/bin/magnetar-pacman-conf"


def main(confdir: pathlib.Path) -> int:
    problems: list[str] = []
    writes: dict[pathlib.Path, str] = {}

    def load(rel: str) -> str | None:
        p = confdir / rel
        if not p.is_file():
            problems.append(f"{rel}: missing")
            return None
        return writes.get(p, p.read_text())

    # --- settings.conf ------------------------------------------------------
    rel = "settings.conf"
    s = load(rel)
    if s is not None:
        if "branding: magnetar" not in s:
            if "branding: cachyos" not in s:
                problems.append(f"{rel}: no 'branding: cachyos' line to replace")
            else:
                s = s.replace("branding: cachyos", "branding: magnetar")
        before = s
        s = re.sub(r"^\s*-\s*packagechooser@desktop\s*$\n", "", s, flags=re.M)
        s = re.sub(r"^- id:\s*desktop\n\s*module:\s*packagechooser\n\s*config:\s*packagechooser_desktop\.conf\n",
                   "", s, flags=re.M)
        if s == before and "packagechooser@desktop" in before:
            problems.append(f"{rel}: could not remove the desktop packagechooser step")
        writes[confdir / rel] = s

    # --- netinstall.conf ------------------------------------------------------
    rel = "modules/netinstall.conf"
    ours = f"file://{confdir}/modules/netinstall.yaml"
    s = load(rel)
    if s is not None:
        if not (confdir / "modules/netinstall.yaml").is_file():
            problems.append("modules/netinstall.yaml: Magnetar's package list is not in place")
        block = re.compile(r"^groupsUrl:[ \t]*\n(?:[ \t]+-[^\n]*\n)+", re.M)
        if f"groupsUrl: {ours}\n" in s:
            pass
        elif len(block.findall(s)) != 1:
            problems.append(f"{rel}: expected exactly one 'groupsUrl:' list")
        else:
            s = block.sub(f"groupsUrl: {ours}\n", s)
        writes[confdir / rel] = s

    # --- shellprocess-before-online.conf --------------------------------------
    rel = "modules/shellprocess-before-online.conf"
    s = load(rel)
    if s is not None:
        cp = re.compile(r'^([ \t]*)- command: "cp /etc/pacman-more\.conf \$\{ROOT\}/etc/pacman\.conf"\n'
                        r'[ \t]*- command: "/etc/calamares/scripts/detect-architecture \$\{ROOT\}/etc/pacman\.conf"\n',
                        re.M)
        mine = f'- command: "{PACMAN_CONF_TOOL} --no-drop-ins ${{ROOT}}/etc/pacman.conf"'
        if mine in s:
            pass
        elif not cp.search(s):
            problems.append(f"{rel}: the pacman-more.conf copy and detect-architecture commands are gone")
        else:
            s = cp.sub(lambda m: f"{m.group(1)}{mine}\n", s, count=1)
        writes[confdir / rel] = s

    # --- shellprocess.conf ------------------------------------------------------
    rel = "modules/shellprocess.conf"
    s = load(rel)
    if s is not None:
        mine = f'- command: "{PACMAN_CONF_TOOL} /etc/pacman.conf"'
        head = re.compile(r"^script:[ \t]*\n([ \t]+)-", re.M)
        if mine in s:
            pass
        elif "dontChroot: false" not in s:
            problems.append(f"{rel}: no longer runs in the target ('dontChroot: false' is gone)")
        elif not head.search(s):
            problems.append(f"{rel}: no 'script:' list to add to")
        else:
            s = head.sub(lambda m: f"script:\n{m.group(1)}{mine}\n{m.group(1)}-", s, count=1)
        writes[confdir / rel] = s

    if problems:
        sys.stderr.write("magnetar-install: CachyOS's Calamares configuration has changed:\n")
        for x in problems:
            sys.stderr.write(f"  - {x}\n")
        sys.stderr.write("  Update assemble-config.py in magnetar-calamares before shipping another ISO.\n")
        return 1

    for p, s in writes.items():
        p.write_text(s)
    print("    settings.conf: branding -> magnetar, desktop chooser removed")
    print("    netinstall.conf: Magnetar's package list only")
    print("    pacman.conf on the target: written by magnetar-pacman-conf")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: assemble-config.py CONFDIR\n")
        raise SystemExit(2)
    raise SystemExit(main(pathlib.Path(sys.argv[1])))
