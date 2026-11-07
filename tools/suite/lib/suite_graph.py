# SPDX-License-Identifier: GPL-3.0-only
"""Which suite repositories depend on which, and whether one may be released.

Run by suite-deps.sh, never on its own:

    suite_graph.py order ROOT DIR...          the repositories in release order
    suite_graph.py upstream ROOT REPO DIR...  exit 1 unless every suite
                                              repository REPO depends on is
                                              released and picked up by REPO
    suite_graph.py follows [--fix] DIR KEY:LEADER...
                                              exit 1 when the root DIR links
                                              the dependency KEY at another
                                              version than LEADER does; --fix
                                              rewrites DIR's requirements to
                                              LEADER's version

DIR... are the resolve roots suite-deps.sh found. A crate belongs to the
repository whose checkout holds it, and REPO depends on another repository
when any of REPO's crates names one of that repository's crates — from
crates.io, by git tag, or as a dev-dependency.

The release order follows from it: a library is published before anything
that requires it is raised, and a consumer is raised to it before the
consumer is released. Releasing in another order ships a consumer built on
the old library, and it has to be released a second time.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

# A change in these alone does not need a release for consumers to pick up.
NOT_RELEASED_CONTENT = (":(exclude)Cargo.lock", ":(exclude)*/Cargo.lock",
                        ":(exclude)*.md", ":(exclude).github")


def run(*args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True).stdout


def load(root, dirs):
    """Crate -> repository, and per repository its crates' dependencies."""
    owner, deps = {}, {}
    for d in map(Path, dirs):
        if d.parent != root:  # a fuzz workspace belongs to its repository
            continue
        meta = json.loads(run("cargo", "metadata", "--no-deps",
                              "--format-version", "1", cwd=d))
        for package in meta["packages"]:
            owner[package["name"]] = d.name
            deps.setdefault(d.name, []).extend(package.get("dependencies", []))
    return owner, deps


def upstream_of(repo, owner, deps):
    return sorted({owner[dep["name"]] for dep in deps.get(repo, [])
                   if owner.get(dep["name"], repo) != repo})


def order(owner, deps):
    """Every repository after all it depends on; ties alphabetically."""
    pending = {r: set(upstream_of(r, owner, deps)) for r in deps}
    done = []
    while pending:
        ready = sorted(r for r, up in pending.items() if up <= set(done))
        if not ready:
            sys.exit(f"dependency cycle among: {', '.join(sorted(pending))}")
        for r in ready:
            done.append(r)
            del pending[r]
    return done


def locked(lockfile):
    """Crate name -> the versions a Cargo.lock resolves it to."""
    versions = {}
    if lockfile.exists():
        for name, version in re.findall(r'^name = "([^"]+)"\nversion = "([^"]+)"',
                                        lockfile.read_text(), re.M):
            versions.setdefault(name, set()).add(version)
    return versions


def problems(root, repo, owner, deps):
    found = []
    lock = locked(root / repo / "Cargo.lock")
    for up in upstream_of(repo, owner, deps):
        up_dir = root / up
        try:
            tag = run("git", "describe", "--tags", "--abbrev=0", cwd=up_dir).strip()
        except subprocess.CalledProcessError:
            found.append(f"{up} has never been released; release it before {repo}")
            continue
        changed = run("git", "diff", "--name-only", tag, "HEAD", "--", ".",
                      *NOT_RELEASED_CONTENT, cwd=up_dir).split()
        if changed:
            found.append(f"{up} has changes since {tag} that are not released "
                         f"({', '.join(changed[:4])}{', ...' if len(changed) > 4 else ''}); "
                         f"release {up} before {repo}")
        versions = {p["name"]: p["version"] for p in json.loads(run(
            "cargo", "metadata", "--no-deps", "--format-version", "1",
            cwd=up_dir))["packages"]}
        for dep in deps[repo]:
            if owner.get(dep["name"]) != up:
                continue
            source = dep.get("source") or ""
            if source.startswith("git+"):
                used = re.search(r"[?&]tag=([^&#]+)", source)
                if used and used.group(1) != tag:
                    found.append(f"{repo} uses {up} {used.group(1)}, not {tag}; "
                                 f"raise {repo} first")
            elif source.startswith("registry+"):
                want = versions.get(dep["name"])
                have = lock.get(dep["name"], set())
                if want and want not in have:
                    found.append(f"{repo} locks {dep['name']} "
                                 f"{', '.join(sorted(have)) or 'nothing'}, not {want}; "
                                 f"raise {repo} first")
    return sorted(set(found))


def follows(directory, pairs, fix):
    """Check, or fix, that each CRATE in `directory` is LEADER's copy.

    Some requirements are right only as the same copy another crate links:
    a test that parses with the renderer's own parser, an enum the client
    library hands back. Excluded from `raise`, they would sit until someone
    noticed the leader had moved; checked here, they move with it.
    """
    # A check must not rewrite the lockfile; a fix is followed by cargo update.
    locked = () if fix else ("--locked",)
    meta = json.loads(run("cargo", "metadata", "--format-version", "1", *locked,
                          cwd=directory))
    packages = {p["id"]: p for p in meta["packages"]}
    members = set(meta["workspace_members"])
    found = []
    for pair in pairs:
        # KEY is the dependency as our manifests name it (`rand_pgp` for a
        # renamed `rand`); LEADER is the crate whose copy it has to be.
        key, leader = pair.split(":")
        extern = key.replace("-", "_")
        crates, ours = set(), set()
        for node in meta["resolve"]["nodes"]:
            if node["id"] not in members:
                continue
            for dep in node["deps"]:
                if dep["name"] == extern:
                    crates.add(packages[dep["pkg"]]["name"])
                    ours.add(packages[dep["pkg"]]["version"])
        wanted = {packages[dep["pkg"]]["version"]
                  for node in meta["resolve"]["nodes"]
                  if packages[node["id"]]["name"] == leader
                  for dep in node["deps"]
                  if packages[dep["pkg"]]["name"] in crates}
        if not wanted or not ours or ours <= wanted:
            continue
        target = max(wanted, key=lambda v: [int(x) for x in re.findall(r"\d+", v)])
        found.append(f"{key} is linked at {', '.join(sorted(ours))}; "
                     f"{leader} links {target}, which it has to follow")
        if fix:
            major_minor = ".".join(target.split(".")[:2])
            for manifest in {packages[m]["manifest_path"] for m in members}:
                rewrite_requirement(Path(manifest), key, major_minor)
    return found


def rewrite_requirement(manifest, key, version):
    """Set the version of the dependency named `key` in `manifest`."""
    out = []
    for line in manifest.read_text().splitlines(keepends=True):
        if re.match(rf"^\s*{re.escape(key)}\s*=\s*\"", line):
            line = re.sub(r'=\s*"[^"]*"', f'= "{version}"', line, count=1)
        elif re.match(rf"^\s*{re.escape(key)}\s*=\s*\{{", line):
            line = re.sub(r'version\s*=\s*"[^"]*"', f'version = "{version}"', line, count=1)
        out.append(line)
    manifest.write_text("".join(out))


def main():
    if sys.argv[1] == "follows":
        follows_main(sys.argv[2:])
        return
    mode, root = sys.argv[1], Path(sys.argv[2])
    if mode == "order":
        owner, deps = load(root, sys.argv[3:])
        for repo in order(owner, deps):
            up = upstream_of(repo, owner, deps)
            print(repo + (f"  (after {', '.join(up)})" if up else ""))
    elif mode == "upstream":
        repo = sys.argv[3]
        owner, deps = load(root, sys.argv[4:])
        found = problems(root, repo, owner, deps)
        for line in found:
            print(f"  {line}")
        sys.exit(1 if found else 0)
    else:
        sys.exit(f"unknown mode {mode}")


def follows_main(args):
    fix = args[:1] == ["--fix"]
    args = args[1:] if fix else args
    found = follows(Path(args[0]), args[1:], fix)
    for line in found:
        print(f"  {line}{' (fixed)' if fix else ''}")
    sys.exit(1 if found and not fix else 0)


if __name__ == "__main__":
    main()
