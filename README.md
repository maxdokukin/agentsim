# AgentSim — see and understand your agents

![main_screen.png](doc/main_screen.png)

## Overview

AgentSim is a ModelSim-inspired desktop tool that helps to visualize, debug, and better understand AI agent behavior,
providing deeper visual insights into how agents execute tasks and make decisions. It reads the transcripts that
agentic coding tools (Claude Code, Hermes, Pi) leave behind and lays each session out on an interactive timeline of
user messages, agent messages, thinking, and tool calls — what the agent read, when it thought, which tools it fired,
and how long each step took. Because most transcripts do not record step durations, each parser reconstructs them from
record timestamps and parent-pointer chains. The app is a Rust/Tauri host that supervises a Python/FastAPI parsing
server behind a TypeScript/vis-timeline frontend, shipped as a Windows `.msi` and Linux `.deb` built by GitHub Actions.

## Highlights

- Three transcript formats behind one `AgenticFramework` interface: Claude Code (JSONL), Hermes (SQLite), Pi (JSONL) — `src/server/app/backends/`
- Per-step durations reconstructed from `parentUuid` / `parentId` chains, with tool calls ending at their result's timestamp so parallel calls overlap instead of chaining
- Self-contained installers: bundled Python 3.11 runtime + server, `.msi` (Windows) and `.deb` (x86_64, arm64) from one CI workflow — `.github/workflows/release.yml`
- Versions v0.1.1–v0.1.6 released between 2026-07-08 and 2026-08-06 (`release/RELEASE_NOTES.md`, git log); 175 commits in total
- Transcript text is rendered as Markdown through DOMPurify, since agent-written content is untrusted — `src/app/src/ui/TimelinePanel.ts`

## How it works

```
~/.claude/projects/*.jsonl ─┐
~/.hermes/state.db ─────────┼→ backend parser → Span[] (type, title, start/end, offset ms) → FastAPI :4317 → TypeScript UI → vis-timeline
~/.pi/agent/sessions/*.jsonl┘                                                                    ▲
                                                     Rust/Tauri host spawns + supervises the Python server
```

- **Tauri host** (`src/app/src-tauri/`, Rust) — frameless native window; spawns `python -m app.main --port 4317` on startup, restarts it with 0.5 s → 30 s backoff if it dies, kills it on exit; uses the bundled runtime in release builds and the repo `.venv` in dev.
- **Server** (`src/server/app/`, Python/FastAPI/Pydantic v2) — framework registry, source add/validate/remove, session list with backend-computed filter facets, per-session traces, user metadata (star, nickname, comments) and a diagnostics feed.
- **Backends** (`src/server/app/backends/`) — `ClaudeCode.py`, `Hermes.py`, `Pi.py` implement `AgenticFramework` (`init`, `get_sessions_list`, `get_session_trace`); Hermes is read from a temporary copy of `state.db` + `-wal`/`-shm` so a running agent's lock is never touched.
- **Frontend** (`src/app/src/`, TypeScript/Vite, no UI framework) — sidebar grouped by date, filter panel, data-sources manager with drag-and-drop import, and a timeline widget with collapsible sections, a miniature overview, "shrink long regions" folding and break markers.
- **Release pipeline** (`release/`, `.github/workflows/release.yml`) — stages a portable Python + server into `src-tauri/runtime/`, runs `tauri build`, and publishes one GitHub Release tagged `v<version>-<run_number>`. Details: [release/README.md](release/README.md).

### Data sources

AgentSim reads sessions straight from where your tools already store them —
nothing to export or configure.

| Source | Reads from | Status |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/<project>/<id>.jsonl` | Supported |
| Hermes | `~/.hermes/state.db` (`%LOCALAPPDATA%\hermes\state.db` on Windows) | Supported |
| Pi | `~/.pi/agent/sessions/<project>/<id>.jsonl` | Supported |

### Adding data sources

Add data one of three ways (examples shown for Claude Code):

- **Single file** — one `.jsonl` transcript.
  - `D:\mydata\6f3a…jsonl`
- **Folder of transcripts** — a flat folder of `.jsonl` files.
    ```
    other_sessions/
    └── session-a.jsonl
        …
    ```
- **Canonical file layout** — a folder organized the way the framework stores it
  (the nested subtree), at any location — not just the default one.
  - `my/custom/path/.claude/`

**Simply drag and drop your data in the app UI, or go to file → Manage Data Sources.**

A detected default location is added as an auto-watching source (new sessions appear as they are written); a manually
imported folder is frozen as a snapshot of the session files present at import time.

### Future direction
- Extending support to Gaia, Cursor, Codex, and OpenCode
- Adding session analysis and stats with AI-driven analytics
- macOS support

## Results

| Metric | Value | Baseline / note |
|---|---|---|
| Supported transcript formats | 3 (Claude Code, Hermes, Pi) | Cursor and Codex prototypes removed before release (commit `31d5bd5`) |
| Released versions | v0.1.1 → v0.1.6 (2026-07-08 → 2026-08-06) | `release/RELEASE_NOTES.md` |
| Installer targets | Windows `.msi`; Linux `.deb` (amd64, arm64) | Linux added 2026-09-08; macOS not packaged |
| Commits | 175 (168 non-merge) | 2026-06-15 → 2026-09-08 |
| Source lines | 4,956 TypeScript · 2,566 Python · 514 Rust · 2,255 CSS | raw `wc -l`, excluding generated files |
| HTTP API | 17 routes on `localhost:4317` | `src/server/app/server.py` |

The project is a tool rather than a model, so its results are delivery measures: formats supported, releases shipped,
platforms packaged and code size.

## Getting started

Download the latest release for your platform from the **Releases** section
in the sidebar on the right, then select the data sources you would like to
view.

- **Windows**: run the `.msi` installer.
  - You will see **"Windows protected your PC"** — click **More info → Run
    anyway**.
- **Ubuntu / Debian**: install the `.deb` for your architecture
  (`amd64` or `arm64`), e.g. `sudo apt install ./AgentSim_<version>_amd64.deb`.

Both installers are unsigned — the app isn't code-signed yet. It's open
source, so feel free to audit the code.

> macOS isn't packaged yet — see [For developers](#for-developers) to run
> from source in the meantime.

### For developers

Run AgentSim locally from source.

#### Prerequisites
- **Node.js 20+** (provides `npm`)
- **Rust toolchain** (`cargo`) — required for the Tauri desktop host
- **Python 3.11+** — required for the FastAPI backend

#### Setup
```bash
git clone https://github.com/amd/agentsim.git
cd agentsim

npm install            # installs frontend + Tauri CLI (npm workspace)
npm run server:install # installs the Python server dependencies
npm run app:icons      # generates the Tauri app icons (not committed to git)
```

#### Run
From the repo root:

```bash
# Desktop app (native Tauri window) — the Rust host starts/stops the Python server itself
scripts\run_app.bat        # Windows, or: scripts/run_app.sh (Linux/macOS)
                           # or: npm run tauri:dev

# Web mode (FastAPI server + Vite UI in the browser at http://localhost:1420)
scripts\run_web.bat        # Windows, or: scripts/run_web.sh (Linux/macOS)
                           # or: npm run dev
```

> The first `run_app` launch is slow — Cargo compiles the Rust `src-tauri`
> crate from scratch. Later runs are cached and fast.

Other commands: `npm run typecheck` (TypeScript), `npm run build` (frontend bundle), `./release/build.ps1` or
`./release/build.sh` (local installer build, see [release/README.md](release/README.md)). User configuration is stored in
`~/.cache/AgentSim/` (`config.json`, `sessions_configs/`). There is no automated test suite in the repo.

## Documents

- [Main screen screenshot](doc/main_screen.png)
- [Release pipeline](release/README.md) and [release notes](release/RELEASE_NOTES.md)
- [CI workflow](.github/workflows/release.yml)
- [License (MIT)](LICENSE)
- Canonical repository: [github.com/amd/agentsim](https://github.com/amd/agentsim)
