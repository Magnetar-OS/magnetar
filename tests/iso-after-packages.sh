#!/usr/bin/env bash
# The ISO installs the distribution packages from the published [magnetar].
# When the ISO workflow ran on the same push as Packages it raced the publish
# and shipped the previous installer, so the wiring must stay:
#  - ISO has no push trigger; it follows a completed run of the workflow named
#    Packages, and waits for the repository to serve this commit's versions;
#  - Packages runs on every path the ISO is built from, or a push that only
#    touches iso/ would build no ISO at all.
set -euo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)"
iso="$M/.github/workflows/iso.yml"
pkgs="$M/.github/workflows/packages.yml"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# The top-level `on:` mapping of a workflow, comments removed.
triggers() { awk '/^on:/ {on=1; next} /^[^ #]/ {on=0} on' "$1" | sed 's/[[:space:]]*#.*//'; }

! triggers "$iso" | grep -qE '^  push:' || bad "iso.yml runs on push again"
triggers "$iso" | grep -A3 -E '^  workflow_run:' | grep -qE '^    workflows: \[Packages\]$' \
  || bad "iso.yml does not follow the Packages workflow"
grep -qxF 'name: Packages' "$pkgs" || bad "packages.yml is no longer named Packages, which iso.yml follows"
grep -qF 'tools/check-published.sh --wait' "$iso" \
  || bad "iso.yml does not wait for [magnetar] to serve this commit's packages"

push_paths="$(triggers "$pkgs" | awk '/^  push:/ {p=1; next} /^  [a-z_]+:/ {p=0} p')"
for path in 'iso/**' 'branding.env' '.github/workflows/iso.yml'; do
  grep -qF "'$path'" <<< "$push_paths" || bad "a push to $path does not run Packages, so no ISO is built from it"
done

(( fail == 0 )) && echo PASS
exit "$fail"
