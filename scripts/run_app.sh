#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# run_app - build & launch the Tauri desktop app (native window).
# The Rust host starts/stops the Python server itself (src-tauri/src/lib.rs)
# and Tauri launches Vite via beforeDevCommand, so this is all that's needed.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

npm run tauri:dev
