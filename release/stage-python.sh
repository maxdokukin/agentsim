#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# stage-python.sh - Stage a self-contained Python runtime + the FastAPI server
# into the Tauri resource staging dir, so the .deb can ship a server that runs
# without any system Python.
#
# Uses a python-build-standalone "install_only_stripped" build (a portable,
# relocatable CPython with pip already installed) for the current machine's
# architecture. Steps:
#   1. Download and extract cpython-<ver>+<tag>-<triple>-install_only_stripped
#      to runtime/python. Unlike the Windows embeddable distribution, this is
#      a normal CPython build - no path-file patching or pip bootstrap needed.
#   2. Install src/server/requirements.txt into it.
#   3. Copy the server source (src/server/app) to runtime/server/app.
#
# The output (src/app/src-tauri/runtime/) is git-ignored and consumed by
# tauri.release.linux.conf.json's bundle.resources. Re-running cleans and
# rebuilds it. Must run natively on the target architecture (reads `uname -m`
# to pick the right build), matching the one-native-job-per-arch CI design.

set -euo pipefail

# Pin a python-build-standalone release tag + CPython version together, the
# same reproducibility approach stage-python.ps1 uses for the Windows embeddable
# zip. Verify https://github.com/astral-sh/python-build-standalone/releases
# still has this exact asset before bumping either value.
PBS_TAG="${PBS_TAG:-20260901}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11.16}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$repo_root/src/app/src-tauri/runtime"
python_dir="$runtime_dir/python"
server_out="$runtime_dir/server"
server_src="$repo_root/src/server/app"
req_file="$repo_root/src/server/requirements.txt"

case "$(uname -m)" in
  x86_64|amd64)   triple="x86_64-unknown-linux-gnu" ;;
  aarch64|arm64)  triple="aarch64-unknown-linux-gnu" ;;
  *) echo "[stage-python] unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

asset="cpython-${PYTHON_VERSION}+${PBS_TAG}-${triple}-install_only_stripped.tar.gz"
url="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${asset}"

echo "[stage-python] staging Python ${PYTHON_VERSION} (${triple}) -> $runtime_dir"

# 1. Clean + download + extract. The tarball's top-level "python/" dir lands
#    directly at runtime/python (install_only variants ship pre-flattened,
#    with no "install/" prefix to strip).
rm -rf "$runtime_dir"
mkdir -p "$runtime_dir"
tmp_tar="$(mktemp -t "pbs-XXXXXX.tar.gz")"
trap 'rm -f "$tmp_tar"' EXIT
echo "[stage-python] downloading $url"
curl -fsSL -o "$tmp_tar" "$url"
tar -xzf "$tmp_tar" -C "$runtime_dir"
rm -f "$tmp_tar"
trap - EXIT

python_bin="$python_dir/bin/python3"
chmod +x "$python_bin"

# 2. Install the server's runtime deps into site-packages. pip already ships
#    with this build (--with-ensurepip), unlike the Windows embeddable zip.
echo "[stage-python] installing $req_file"
"$python_bin" -m pip install --no-warn-script-location -q -r "$req_file"

# 3. Copy the server source next to the runtime. Pre-create the target dir and
#    copy the *contents* of server_src into it, mirroring stage-python.ps1's
#    deterministic-copy approach.
server_app_out="$server_out/app"
if [ ! -d "$server_src" ]; then
  echo "[stage-python] server source not found: $server_src" >&2
  exit 1
fi
mkdir -p "$server_app_out"
cp -r "$server_src"/. "$server_app_out"/
find "$server_out" -type d -name "__pycache__" -exec rm -rf {} +

# 4. Verify the staged tree has the files the bundle's resource globs expect,
#    so a staging slip fails here with a clear message rather than as an
#    opaque "glob pattern ... didn't match any files" during `tauri build`.
must_exist=(
  "$python_bin"
  "$server_app_out/main.py"
)
for p in "${must_exist[@]}"; do
  if [ ! -e "$p" ]; then
    echo "[stage-python] runtime tree under $runtime_dir :" >&2
    find "$runtime_dir" >&2
    echo "[stage-python] staging incomplete: expected file missing -> $p" >&2
    exit 1
  fi
done

echo "[stage-python] done."
