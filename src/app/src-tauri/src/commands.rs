// Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
//
// See LICENSE for license information.

//! Tauri invoke handlers backing the custom borderless title bar's window
//! controls. Cloned 1:1 from reference/lemonade's window-control logic.

use std::sync::Arc;

use tauri::{AppHandle, Manager, State, WebviewWindow};

use crate::server_process::ServerProcess;

// Event channel: emitted on resize so the renderer can swap the maximize/restore
// icon. The matching string lives in src/app/src/ui/MenuBar.ts — keep in sync.
pub(crate) const MAXIMIZE_CHANGE: &str = "maximize-change";

// Whether the embedded Python server child is currently alive. The frontend can
// call this after a failed request to tell "server crashed" apart from a
// transient/data failure; the supervisor restarts a dead child automatically.
#[tauri::command]
pub(crate) fn server_status(server: State<'_, Arc<ServerProcess>>) -> bool {
    server.is_running()
}

fn main_window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window("main")
}

#[tauri::command]
pub(crate) fn minimize_window(app: AppHandle) {
    if let Some(w) = main_window(&app) {
        let _ = w.minimize();
    }
}

#[tauri::command]
pub(crate) fn maximize_window(app: AppHandle) {
    if let Some(w) = main_window(&app) {
        if let Ok(true) = w.is_maximized() {
            let _ = w.unmaximize();
        } else {
            let _ = w.maximize();
        }
    }
}

#[tauri::command]
pub(crate) fn close_window(app: AppHandle) {
    if let Some(w) = main_window(&app) {
        let _ = w.close();
    }
}

// Guard the values interpolated into the spawned shell command. Session ids and
// model names are UUID/identifier-shaped; reject anything with shell-significant
// characters so a crafted transcript can't inject a command.
fn is_safe_token(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':'))
}

/// Open a new terminal window that resumes a Claude Code session, running
/// `claude --resume <session_id> [--model <model>]` with the working directory
/// set to the session's project so Claude resolves it. (`--resume` targets a
/// specific id; `--continue` would ignore it and reopen the latest session.)
///
/// If the project directory no longer exists the terminal opens in the home
/// directory instead, and that directory is returned so the UI can say so;
/// `None` means the session's own project directory was used.
#[tauri::command]
pub(crate) fn launch_session(
    session_id: String,
    model: String,
    project_path: String,
) -> Result<Option<String>, String> {
    use std::path::{Path, PathBuf};
    use std::process::Command;

    if !is_safe_token(&session_id) {
        return Err(format!("unsafe session id: {session_id}"));
    }
    let mut claude = format!("claude --resume {session_id}");
    if !model.is_empty() {
        if !is_safe_token(&model) {
            return Err(format!("unsafe model name: {model}"));
        }
        claude.push_str(&format!(" --model {model}"));
    }

    // Spawning with a missing current_dir fails outright (ENOENT), so fall back
    // to home when the project was moved or deleted.
    let (cwd, fell_back): (Option<PathBuf>, bool) =
        if !project_path.is_empty() && Path::new(&project_path).is_dir() {
            (Some(PathBuf::from(&project_path)), false)
        } else {
            (home_dir(), !project_path.is_empty())
        };

    #[cfg(target_os = "windows")]
    let mut cmd = {
        let mut c = Command::new("cmd");
        c.args(["/C", "start", "cmd", "/K", &claude]);
        c
    };

    #[cfg(target_os = "macos")]
    let mut cmd = {
        let body = match &cwd {
            Some(dir) => format!("cd {} && {claude}", shell_quote(&dir.to_string_lossy())),
            None => claude.clone(),
        };
        let mut c = Command::new("osascript");
        c.args([
            "-e",
            &format!("tell application \"Terminal\" to do script \"{}\"", body.replace('"', "\\\"")),
        ]);
        c
    };

    // Ptyxis (Ubuntu/Fedora default) puts a command passed with `-e`/`-x` or
    // `--new-window` in a stripped-down window with no tabs. `--tab` runs it as
    // a tab in a normal window instead (the active one, or a new one if none),
    // which the user can move out via the tab's "Move to New Window". Other
    // terminals go through the Debian alternatives link.
    #[cfg(target_os = "linux")]
    let mut cmd = {
        let shell = format!("{claude}; exec bash");
        if on_path("ptyxis") {
            let mut c = Command::new("ptyxis");
            c.arg("--tab");
            if let Some(dir) = &cwd {
                c.arg("-d").arg(dir);
            }
            c.args(["--", "bash", "-c", &shell]);
            c
        } else {
            let mut c = Command::new("x-terminal-emulator");
            c.args(["-e", "bash", "-c", &shell]);
            c
        }
    };

    if let Some(dir) = &cwd {
        cmd.current_dir(dir);
    }

    // The launcher exits as soon as the terminal is up (Ptyxis hands off to its
    // running service); reap it so it doesn't linger as a zombie.
    let mut child = cmd.spawn().map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(if fell_back {
        Some(cwd.map(|d| d.to_string_lossy().into_owned()).unwrap_or_default())
    } else {
        None
    })
}

fn home_dir() -> Option<std::path::PathBuf> {
    let var = if cfg!(target_os = "windows") { "USERPROFILE" } else { "HOME" };
    std::env::var_os(var)
        .map(std::path::PathBuf::from)
        .filter(|p| p.is_dir())
}

#[cfg(target_os = "linux")]
fn on_path(bin: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|dir| dir.join(bin).is_file()))
        .unwrap_or(false)
}

#[cfg(target_os = "macos")]
fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
