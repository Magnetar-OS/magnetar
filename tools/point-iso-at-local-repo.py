#!/usr/bin/env python3
"""Point the ISO's [magnetar] repository at a local directory.

Locally built packages are unsigned. Relaxing SigLevel for them is correct for
a test image and wrong for anything published, so it happens here — in the
generated build tree — and never in the committed pacman.conf, which requires
signatures and stays that way.

    point-iso-at-local-repo.py <pacman.conf> <repo name> <local dir>
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    conf, name, path = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    s = conf.read_text()

    pattern = rf"\[{re.escape(name)}\]\nSigLevel = [^\n]*\nServer = [^\n]*"
    replacement = (
        f"[{name}]\n"
        f"# LOCAL TEST BUILD: unsigned packages from {path}.\n"
        f"# The committed pacman.conf requires signatures. This override exists\n"
        f"# only in the generated build tree and must never be published.\n"
        f"SigLevel = Optional TrustAll\n"
        f"Server = file://{path}"
    )

    s, n = re.subn(pattern, replacement, s, count=1)
    if n != 1:
        print(f"point-iso-at-local-repo: no [{name}] section to rewrite in {conf}",
              file=sys.stderr)
        return 1

    conf.write_text(s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
