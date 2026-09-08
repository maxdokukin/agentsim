#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# release - cut a release by advancing the `releases` branch to `main`.
# CI (.github/workflows/release.yml) builds and publishes the .msi/.deb on
# every push to `releases`. The flow is: main is the source of truth; releases
# is fast-forwarded to it (never committed to directly). See release/README.md.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# 1. Releases must be reproducible from committed state - refuse if dirty.
if [ -n "$(git status --porcelain)" ]; then
  echo "[release] working tree has uncommitted changes. Commit or stash first:"
  git status --short
  exit 1
fi

# 2. The release commit is expected on main; releases just points at it.
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "main" ]; then
  echo "[release] not on main (on $branch). Switch to main first: git checkout main"
  exit 1
fi

# 3. Ask for the version to publish. CI (release.yml) tags/names the GitHub
#    Release from tauri.conf.json's version, so bumping it here is what
#    actually sets the released version. The two package.json files are kept
#    in sync.
current="$(node -e "console.log(require('./src/app/src-tauri/tauri.conf.json').version)")"
read -r -p "[release] version to publish (current $current): " version
if [ -z "$version" ]; then
  echo "[release] no version entered. Aborting."
  exit 1
fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[release] '$version' is not a valid x.y.z version."
  exit 1
fi

echo "[release] about to publish v$version (current: v$current)."
echo "[release] this will commit, push main, and fast-forward releases -> main, triggering the CI release build."
read -r -p "[release] continue? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "[release] aborted."
  exit 1
fi

if [ "$version" != "$current" ]; then
  echo "[release] bumping $current -> $version..."
  for f in package.json src/app/package.json src/app/src-tauri/tauri.conf.json; do
    sed -i.bak "s/\"version\": *\"$current\"/\"version\": \"$version\"/" "$f"
    rm -f "$f.bak"
  done
  git add package.json src/app/package.json src/app/src-tauri/tauri.conf.json
  git commit -m "release v$version"
else
  echo "[release] version unchanged; publishing existing v$version."
fi

# 4. Publish main, then fast-forward the remote releases branch to it. A plain
#    push refuses non-fast-forwards, so this can't clobber unmerged release work.
echo "[release] pushing main..."
git push origin main

echo "[release] advancing releases -> main..."
if ! git push origin main:releases; then
  echo "[release] push to releases failed (not a fast-forward?). Reconcile releases with main and retry."
  exit 1
fi

# 5. Keep the local releases ref in sync so it isn't left behind main.
git branch -f releases main

echo "[release] release triggered. CI is building the installers."

# 6. If the GitHub CLI is present, follow the run; otherwise print where to look.
if ! command -v gh >/dev/null 2>&1; then
  echo "[release] install GitHub CLI (gh) to auto-watch, or check the Actions tab."
  exit 0
fi
echo "[release] waiting for the workflow to register..."
sleep 6
gh run watch
