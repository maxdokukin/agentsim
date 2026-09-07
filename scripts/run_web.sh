#!/usr/bin/env bash
# Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
#
# See LICENSE for license information.

# run_web - start the FastAPI server + web UI (Vite), then open a browser tab.
# Browser-only workflow (no desktop window). Ctrl+C stops both.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# dev:server invokes bare `python`; prefer the repo-root venv when present
# (see src/app/src-tauri/src/server_process.rs for the same convention on
# the desktop/Tauri side) so this doesn't depend on activating it manually.
if [ -x ".venv/bin/python" ]; then
    PATH="$PWD/.venv/bin:$PATH"
fi

open_url() {
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$1" >/dev/null 2>&1
    elif command -v open >/dev/null 2>&1; then
        open "$1" >/dev/null 2>&1
    fi
}

# Detached: wait (up to 60s) for the web UI to answer, then open a browser tab.
(
    for _ in $(seq 1 60); do
        if curl -sf -o /dev/null http://localhost:1420; then
            open_url "http://localhost:1420"
            break
        fi
        sleep 1
    done
) &

# Server + web UI run in the foreground; Ctrl+C stops both.
npm run dev
