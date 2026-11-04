//! Tells the window when a note or folder changes (an agent saved a note, the Mac app
//! edited one through a synced folder…). Only `.md` files and `_folder.yml` count:
//! session notes, rewritten by the hooks on every agent turn, the write lock and the
//! trash don't. Bursts are coalesced, but a steady stream still reloads every 2 s.

use notify::{RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};

const QUIET: Duration = Duration::from_millis(300);
const MAX_WAIT: Duration = Duration::from_secs(2);

fn matters(root: &Path, path: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(root) else { return false };
    let hidden = relative.components().any(|c| {
        let name = c.as_os_str().to_string_lossy();
        name.starts_with('.') || name == "_sessions"
    });
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    !hidden && (name.ends_with(".md") || name == "_folder.yml" || path.extension().is_none())
}

pub fn start(app: AppHandle, root: PathBuf) -> Result<(), String> {
    let (tx, rx) = mpsc::channel();
    let watched = root.clone();
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if let Ok(event) = event {
            if event.paths.iter().any(|p| matters(&watched, p)) {
                let _ = tx.send(());
            }
        }
    })
    .map_err(|e| e.to_string())?;
    watcher.watch(&root, RecursiveMode::Recursive).map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _watcher = watcher; // Lives as long as this thread, i.e. the app.
        while rx.recv().is_ok() {
            let first = Instant::now();
            while first.elapsed() < MAX_WAIT && rx.recv_timeout(QUIET).is_ok() {}
            let _ = app.emit("notes-changed", ());
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::matters;
    use std::path::Path;

    #[test]
    fn only_notes_and_folders_count() {
        let root = Path::new("/n");
        assert!(matters(root, Path::new("/n/code-notes/a.md")));
        assert!(matters(root, Path::new("/n/plans/_folder.yml")));
        assert!(matters(root, Path::new("/n/ideas")));
        assert!(!matters(root, Path::new("/n/_sessions/x.md")));
        assert!(!matters(root, Path::new("/n/.cots.lock")));
        assert!(!matters(root, Path::new("/n/.trash/code-notes/a.md")));
        assert!(!matters(root, Path::new("/n/code-notes/.a.md.tmp")));
    }
}
