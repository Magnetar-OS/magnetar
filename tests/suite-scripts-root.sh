#!/usr/bin/env bash
# tools/suite/ holds the scripts that act on the whole suite: every repository
# checked out beside this one. They must find that directory from where they
# really are — <suite>/magnetar/tools/suite — whether they are started by that
# path or through the <suite>/scripts symlink the old location left behind,
# and from any working directory.
#
# A throwaway suite: a copy of the scripts, the symlink, one application
# repository with a remote and a release tag, and stand-ins for cargo, node,
# gh and cargo-upgrade. Nothing here touches a real checkout, and the dry runs
# must leave the application's history exactly as it was.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

mkdir -p "$w/suite/magnetar/tools" "$w/bin" "$w/remotes"
cp -a "$M/tools/suite" "$w/suite/magnetar/tools/suite"
ln -s magnetar/tools/suite "$w/suite/scripts"
suite="$(cd "$w/suite" && pwd -P)"

cat > "$w/bin/cargo" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  # A repository can give its own metadata in meta.json; the default is app1's.
  metadata) if [ -f meta.json ]; then cat meta.json; else
      printf '{"target_directory": "%s/target", "packages": [{"id": "app1", "name": "app1", "version": "1.0.0", "publish": []}], "workspace_members": ["app1"], "resolve": {"nodes": [{"id": "app1", "deps": []}]}}\n' "$PWD"; fi ;;
esac
exit 0
STUB
# suite-deps.sh looks for cargo-edit's binary, and asks gh whether a tag's
# release is published.
printf '#!/usr/bin/env bash\nexit 0\n' > "$w/bin/cargo-upgrade"
printf '#!/usr/bin/env bash\necho false\n' > "$w/bin/gh"
chmod +x "$w/bin/cargo-upgrade" "$w/bin/gh"
cat > "$w/bin/node" <<'STUB'
#!/usr/bin/env bash
echo "release-kit plan: $*"
STUB
chmod +x "$w/bin/cargo" "$w/bin/node"
: > "$w/release.mjs"

# The harness's repositories must not depend on this machine's git settings
# (signing, hooks, a credential helper).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git() { command git -c user.name=test -c user.email=test@example.invalid -c init.defaultBranch=main "$@"; }
app="$suite/app1"
mkdir "$app"
printf '[package]\nname = "app1"\nversion = "1.0.0"\n' > "$app/Cargo.toml"
printf '[[package]]\nname = "libcosmic"\nsource = "git+https://github.com/pop-os/libcosmic.git#0123456789abcdef"\n' > "$app/Cargo.lock"
printf '# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- A thing.\n\n## [1.0.0]\n\n- First.\n' > "$app/CHANGELOG.md"
git init -q --bare "$w/remotes/app1.git"
git -C "$app" init -q
git -C "$app" add -- Cargo.toml Cargo.lock CHANGELOG.md
git -C "$app" commit -q -m 'initial'
git -C "$app" tag v1.0.0
git -C "$app" remote add origin "$w/remotes/app1.git"
git -C "$app" push -q -u origin main
state() { command git -C "$app" rev-parse HEAD; command git -C "$app" tag; command git -C "$app" status --porcelain; }
before="$(state)"

run() { (cd / && PATH="$w/bin:$PATH" RELEASE_KIT="$w/release.mjs" SUITE_ORG_URL="$w/remotes" bash "$@") > "$w/out" 2>&1; }

for via in scripts magnetar/tools/suite; do
  d="$suite/$via"

  if run "$d/cargo-update-all.sh" -n; then
    grep -qF "=== summary (root: $suite)" "$w/out" || bad "$via/cargo-update-all.sh: $(grep -F '=== summary' "$w/out" || echo 'no summary')"
    grep -qE '^ok +app1 ' "$w/out" || bad "$via/cargo-update-all.sh did not act on app1"
  else
    bad "$via/cargo-update-all.sh -n exited non-zero:"; cat "$w/out"
  fi

  if run "$d/cargo-clean-all.sh" -n; then
    grep -qF "=== summary (root: $suite)" "$w/out" || bad "$via/cargo-clean-all.sh: $(grep -F '=== summary' "$w/out" || echo 'no summary')"
    grep -qE '^clean +app1 ' "$w/out" || bad "$via/cargo-clean-all.sh did not look at app1"
  else
    bad "$via/cargo-clean-all.sh -n exited non-zero:"; cat "$w/out"
  fi

  if run "$d/suite-deps.sh" check; then
    grep -qxF '==> app1' "$w/out" || { bad "$via/suite-deps.sh check did not look at app1:"; cat "$w/out"; }
  else
    bad "$via/suite-deps.sh check reported drift in a suite with none:"; cat "$w/out"
  fi

  if run "$d/suite-deps.sh" order; then
    grep -qxF 'app1' "$w/out" || { bad "$via/suite-deps.sh order did not list app1:"; cat "$w/out"; }
  else
    bad "$via/suite-deps.sh order exited non-zero:"; cat "$w/out"
  fi

  run "$d/suite-deps.sh" upstream app1 || { bad "$via/suite-deps.sh upstream app1 refused an app with no suite dependencies:"; cat "$w/out"; }

  if run "$d/suite-deps.sh" publish app1; then
    grep -qF 'app1 v1.0.0: no crate to publish' "$w/out" || { bad "$via/suite-deps.sh publish app1:"; cat "$w/out"; }
  else
    bad "$via/suite-deps.sh publish app1 exited non-zero:"; cat "$w/out"
  fi

  if run "$d/release-apps.sh" -n app1; then
    grep -qF 'Dry run: app1 would be released' "$w/out" || { bad "$via/release-apps.sh -n app1 did not reach its plan:"; cat "$w/out"; }
  else
    bad "$via/release-apps.sh -n app1 exited non-zero: $(tail -n1 "$w/out")"
  fi
done

[[ "$(state)" == "$before" ]] || bad "a dry run changed app1's history, tags or working tree"

# A git dependency on an older tag of a suite library is drift, and check
# must say which.
lib="$w/lib1"
mkdir "$lib"
git -C "$lib" init -q
git -C "$lib" commit -q --allow-empty -m 'initial'
git -C "$lib" tag v1.0.0
git -C "$lib" commit -q --allow-empty -m 'next'
git -C "$lib" tag v1.1.0
git clone -q --bare "$lib" "$w/remotes/lib1.git"
printf '[dependencies]\nlib1 = { git = "https://github.com/Magnetar-OS/lib1.git", tag = "v1.0.0" }\n' >> "$app/Cargo.toml"
if run "$suite/scripts/suite-deps.sh" check; then
  bad "suite-deps.sh check passed with app1 on lib1 v1.0.0 while v1.1.0 exists"
fi
grep -qF 'app1/Cargo.toml: lib1 v1.0.0 -> v1.1.0' "$w/out" || { bad "suite-deps.sh check did not name the stale tag:"; cat "$w/out"; }

# Libraries first: an app whose suite library has unreleased changes, or
# which is still on an older tag of it, must not be released.
mk() {  # mk REPO METADATA-JSON
  mkdir "$suite/$1"
  printf '[package]\nname = "%s"\nversion = "1.0.0"\n' "$1" > "$suite/$1/Cargo.toml"
  : > "$suite/$1/Cargo.lock"
  printf '%s\n' "$2" > "$suite/$1/meta.json"
  git -C "$suite/$1" init -q
  git -C "$suite/$1" add -- Cargo.toml Cargo.lock meta.json
  git -C "$suite/$1" commit -q -m initial
}
mk lib2 '{"packages": [{"name": "lib2", "version": "1.0.0", "publish": []}]}'
git -C "$suite/lib2" tag v1.0.0
mk app2 '{"packages": [{"name": "app2", "version": "1.0.0", "publish": [], "dependencies": [{"name": "lib2", "source": "git+https://github.com/Magnetar-OS/lib2.git?tag=v1.0.0"}]}]}'

run "$suite/scripts/suite-deps.sh" upstream app2 || { bad "upstream refused app2 on lib2's newest tag:"; cat "$w/out"; }
grep -qxF 'app2  (after lib2)' <(run "$suite/scripts/suite-deps.sh" order; cat "$w/out") \
  || { bad "order did not put app2 after lib2:"; cat "$w/out"; }

echo 'pub fn changed() {}' > "$suite/lib2/lib.rs"
git -C "$suite/lib2" add lib.rs && git -C "$suite/lib2" commit -q -m change
if run "$suite/scripts/suite-deps.sh" upstream app2; then
  bad "upstream let app2 go while lib2 has unreleased changes"
fi
grep -qF 'lib2 has changes since v1.0.0 that are not released' "$w/out" || { bad "upstream did not name lib2's unreleased changes:"; cat "$w/out"; }

git -C "$suite/lib2" tag v1.1.0
if run "$suite/scripts/suite-deps.sh" upstream app2; then
  bad "upstream let app2 go on lib2 v1.0.0 while v1.1.0 is out"
fi
grep -qF 'app2 uses lib2 v1.0.0, not v1.1.0' "$w/out" || { bad "upstream did not name the stale tag:"; cat "$w/out"; }

# A follower is checked against its leader's copy, and raise's fix moves it
# there: app3's usvg must be the one resvg links.
mk app3 '{"packages": [
  {"id": "app3", "name": "app3", "version": "1.0.0", "publish": [], "manifest_path": "'"$suite"'/app3/Cargo.toml"},
  {"id": "resvg", "name": "resvg", "version": "0.45.1"},
  {"id": "usvg-old", "name": "usvg", "version": "0.45.1"},
  {"id": "usvg-new", "name": "usvg", "version": "0.49.0"}],
 "workspace_members": ["app3"],
 "resolve": {"nodes": [
  {"id": "app3", "deps": [{"name": "usvg", "pkg": "usvg-new"}, {"name": "resvg", "pkg": "resvg"}]},
  {"id": "resvg", "deps": [{"name": "usvg", "pkg": "usvg-old"}]}]}}'
printf '[dependencies]\nusvg = "0.49"\n' >> "$suite/app3/Cargo.toml"
graph() { PATH="$w/bin:$PATH" python3 -B "$suite/magnetar/tools/suite/lib/suite_graph.py" "$@" > "$w/out" 2>&1; }
if graph follows "$suite/app3" usvg:resvg; then
  bad "follows passed with app3 on usvg 0.49 while resvg links 0.45.1"
fi
grep -qF 'usvg is linked at 0.49.0; resvg links 0.45.1' "$w/out" || { bad "follows did not name the mismatch:"; cat "$w/out"; }
graph follows --fix "$suite/app3" usvg:resvg
grep -qxF 'usvg = "0.45"' "$suite/app3/Cargo.toml" || { bad "follows --fix did not move app3's usvg to 0.45:"; cat "$suite/app3/Cargo.toml"; }

(( fail == 0 )) && echo PASS
exit "$fail"
