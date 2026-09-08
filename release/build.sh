#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# build.sh - Build the AgentSim Linux installer (.deb) end to end.
#
# Runnable locally and from CI (.github/workflows/release.yml calls this,
# once per architecture). Steps:
#   1. npm ci                       install frontend + tooling deps (clean)
#      + work around npm/cli#4828   see comment below - re-installs this
#                                    platform's native optional deps
#   2. npm run app:icons            regenerate icons/ (git-ignored) from the
#                                    tracked assets/icon/dark.png
#   3. release/stage-python.sh      stage the portable Python + server source
#   4. npm run tauri:build          build the frontend and bundle the .deb
#   5. copy the .deb to release/dist/
#
# Prereqs: Node 20+, Rust (stable), the Tauri Linux system libraries (see
# .github/workflows/release.yml for the exact apt package list), and curl.
# Must run natively on the target architecture - see stage-python.sh.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/release/dist"
deb_dir="$repo_root/src/app/src-tauri/target/release/bundle/deb"

cd "$repo_root"

echo "[build] npm ci"
npm ci

# Work around a long-standing npm optional-dependencies bug
# (https://github.com/npm/cli/issues/4828): package-lock.json doesn't
# reliably record every platform's native optional package, so `npm ci` can
# silently omit this platform's @rollup/@tauri-apps/cli binary even though
# it's required. Re-install the exact versions already resolved in
# node_modules for the current architecture; --no-save keeps the lockfile
# untouched. Must install both together in one call - installing them
# separately has been observed to evict each other.
case "$(uname -m)" in
  x86_64|amd64)   npm_arch="x64" ;;
  aarch64|arm64)  npm_arch="arm64" ;;
  *) echo "[build] unsupported architecture for npm optional-deps workaround: $(uname -m)" >&2; exit 1 ;;
esac
rollup_ver="$(node -p "require('./node_modules/rollup/package.json').version")"
tauri_cli_ver="$(node -p "require('./node_modules/@tauri-apps/cli/package.json').version")"
echo "[build] working around npm/cli#4828: installing native optional deps for linux-$npm_arch-gnu"
npm install --no-save \
  "@rollup/rollup-linux-${npm_arch}-gnu@${rollup_ver}" \
  "@tauri-apps/cli-linux-${npm_arch}-gnu@${tauri_cli_ver}"

echo "[build] generating icons"
npm run app:icons

echo "[build] staging python runtime"
"$repo_root/release/stage-python.sh"

echo "[build] tauri build (deb)"
# Merge the release overlay (deb target + bundled runtime resources) onto the
# base config. Kept separate so `tauri dev` doesn't require the staged runtime.
release_conf="$repo_root/src/app/src-tauri/tauri.release.linux.conf.json"
npm run tauri:build --workspace src/app -- --verbose --config "$release_conf"

# Collect the installer.
rm -rf "$dist_dir"
mkdir -p "$dist_dir"
shopt -s nullglob
debs=("$deb_dir"/*.deb)
shopt -u nullglob
if [ ${#debs[@]} -eq 0 ]; then
  echo "[build] no .deb produced in $deb_dir" >&2
  exit 1
fi
for f in "${debs[@]}"; do
  cp "$f" "$dist_dir/"
  echo "[build] -> $dist_dir/$(basename "$f")"
done
echo "[build] done."
