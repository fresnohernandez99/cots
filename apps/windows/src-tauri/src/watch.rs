//! Tells the window when anything under the notes folder changes (an agent saved a
//! note, the Mac app edited one through a synced folder…). Bursts are coalesced:
//! one reload per quiet 300 ms.

use notify::{RecursiveMode, Watcher};
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

pub fn start(app: AppHandle, root: PathBuf) -> Result<(), String> {
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if event.is_ok() {
            let _ = tx.send(());
        }
    })
    .map_err(|e| e.to_string())?;
    watcher.watch(&root, RecursiveMode::Recursive).map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _watcher = watcher; // Lives as long as this thread, i.e. the app.
        while rx.recv().is_ok() {
            while rx.recv_timeout(Duration::from_millis(300)).is_ok() {}
            let _ = app.emit("notes-changed", ());
        }
    });
    Ok(())
}
