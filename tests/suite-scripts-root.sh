#!/usr/bin/env bash
# tools/suite/ holds the scripts that act on the whole suite: every repository
# checked out beside this one. They must find that directory from where they
# really are — <suite>/magnetar/tools/suite — whether they are started by that
# path or through the <suite>/scripts symlink the old location left behind,
# and from any working directory.
#
# A throwaway suite: a copy of the scripts, the symlink, one application
# repository with a remote and a release tag, and stand-ins for cargo and
# node. Nothing here touches a real checkout, and the dry runs must leave the
# application's history exactly as it was.
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
  metadata) printf '{"target_directory": "%s/target"}\n' "$PWD" ;;
esac
exit 0
STUB
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

run() { (cd / && PATH="$w/bin:$PATH" RELEASE_KIT="$w/release.mjs" bash "$@") > "$w/out" 2>&1; }

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

  if run "$d/release-apps.sh" -n app1; then
    grep -qF 'Dry run: app1 would be released' "$w/out" || { bad "$via/release-apps.sh -n app1 did not reach its plan:"; cat "$w/out"; }
  else
    bad "$via/release-apps.sh -n app1 exited non-zero: $(tail -n1 "$w/out")"
  fi
done

[[ "$(state)" == "$before" ]] || bad "a dry run changed app1's history, tags or working tree"

(( fail == 0 )) && echo PASS
exit "$fail"
