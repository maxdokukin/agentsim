# Release pipeline

Builds standalone installers that run **without** Python installed:

- Windows: `AgentSim_<version>_x64_en-US.msi` — ships an embeddable Python
  runtime plus the FastAPI server alongside the Tauri app.
- Linux (Ubuntu): `AgentSim_<version>_<arch>.deb` (`amd64` and `arm64`) — ships
  a portable [python-build-standalone](https://github.com/astral-sh/python-build-standalone)
  runtime plus the FastAPI server the same way.

## How it works

The Tauri host normally launches the Python server from the repo's `.venv`
(`src/app/src-tauri/src/server_process.rs`). In a release build it instead runs a
bundled interpreter:

- `stage-python.ps1` (Windows) downloads the **Windows embeddable Python**,
  enables site-packages, `pip install`s `src/server/requirements.txt` into it,
  and copies the server source.
- `stage-python.sh` (Linux) downloads a **python-build-standalone**
  `install_only_stripped` build for the current architecture (a normal,
  relocatable CPython with pip preinstalled — no path-file patching needed)
  and does the same `pip install` + server-source copy.
- Either way the output goes to `src/app/src-tauri/runtime/` (git-ignored).
  `tauri.release.conf.json` / `tauri.release.linux.conf.json` ship that
  `runtime/` as bundle resources, so the installer places `python/` and
  `server/` under the app's `resources/` dir (`/usr/lib/AgentSim/runtime/` for
  the `.deb`).
- At startup `resolve_paths()` (in `server_process.rs`) picks the bundled
  `resources/runtime/python/python.exe` (Windows) or
  `resources/runtime/python/bin/python3` (Linux) + `resources/runtime/server`
  in release builds, and falls back to the repo venv in dev builds.

## Build locally

**Windows** — requires Node 20+, Rust (stable + MSVC build tools), and Python
on PATH:

```powershell
./release/build.ps1
# -> release/dist/AgentSim_<version>_x64_en-US.msi
```

**Linux** — requires Node 20+, Rust (stable), curl, and the Tauri Linux system
libraries (see `.github/workflows/release.yml` for the exact `apt` package
list). Must run natively on the target architecture (x86_64 or arm64):

```bash
./release/build.sh
# -> release/dist/AgentSim_<version>_<arch>.deb
```

Both scripts run `npm ci`, regenerate icons, stage the Python runtime, run
`tauri build` with the platform's release config overlay, and copy the
installer into `release/dist/`.

## Build in CI

Pushing to the **`releases`** branch triggers
`.github/workflows/release.yml` (a thin wrapper around `build.ps1`/`build.sh`).
It builds the `.msi` on `windows-latest` and the `.deb` natively on
`ubuntu-22.04` (x86_64) and `ubuntu-22.04-arm` (arm64) — pinned to an older
Ubuntu baseline rather than `-latest` so the linked binary stays
glibc-forward-compatible with users' machines — then a `publish` job combines
all three artifacts into one GitHub Release tagged `v<version>-<run_number>`.

The version comes from `src/app/src-tauri/tauri.conf.json` (`version`). Bump it
there before cutting a release.

## Files

| File | Purpose |
| --- | --- |
| `build.ps1` / `build.sh` | End-to-end build orchestrator (local + CI), per platform. |
| `stage-python.ps1` / `stage-python.sh` | Download + stage the bundled Python runtime and server, per platform. |
| `dist/` | Build output (git-ignored). |

## Not yet covered

- **Code signing.** The MSI is unsigned and the `.deb` is unsigned/not
  published to an APT repo. (The reference SDK uses SignPath for the MSI; add
  a signing step here when a certificate is available.)
- **AppImage / `.rpm` / macOS installers** — only `.deb` is covered on Linux
  for now.
