#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# build.sh - Build the AgentSim Linux installer (.deb) end to end.
#
# Runnable locally and from CI (.github/workflows/release.yml calls this,
# once per architecture). Steps:
#   1. npm ci                       install frontend + tooling deps (clean)
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
