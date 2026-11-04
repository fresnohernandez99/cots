//! coTs for Windows: a tray icon that opens a small notes window, like the menu bar
//! app on macOS. The notes folder and the `cots` CLI are the same on both.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod cli;
mod markdown;
mod system;
mod watch;

use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WindowEvent};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_positioner::{Position, WindowExt};

#[derive(Default)]
struct AppState {
    /// What each note looked like at the last load, to notify only about what's new.
    /// None until the first load: notes already there at launch aren't news.
    seen: Mutex<Option<HashMap<String, Seen>>>,
    setup_errors: Mutex<Vec<String>>,
    tray: Mutex<Option<TrayIcon>>,
}

#[derive(PartialEq)]
struct Seen {
    review: Option<String>,
}

// MARK: - Reading

/// Every folder and note, in one CLI call (one disk pass).
#[tauri::command]
fn load(app: AppHandle, state: tauri::State<AppState>) -> Result<Value, String> {
    let data = cli::json(&["export"])?;
    let notes = data["notes"].as_array().cloned().unwrap_or_default();
    notify_new(&app, &state, &notes);
    let unread = notes.iter().filter(|n| n["meta"]["status"] == "unread").count();
    if let Some(tray) = state.tray.lock().unwrap().as_ref() {
        let tip = if unread == 0 { "coTs".to_string() } else { format!("coTs · {unread} sin leer") };
        let _ = tray.set_tooltip(Some(tip));
    }
    Ok(data)
}

fn review_of(note: &Value) -> Option<String> {
    (note["style"] == "plan").then(|| note["meta"]["review"]["status"].as_str().unwrap_or("pending").to_string())
}

/// A note an agent just wrote, or a plan that just started waiting for a decision.
fn notify_new(app: &AppHandle, state: &AppState, notes: &[Value]) {
    let current: HashMap<String, Seen> = notes
        .iter()
        .filter_map(|n| Some((n["id"].as_str()?.to_string(), Seen { review: review_of(n) })))
        .collect();
    let mut seen = state.seen.lock().unwrap();
    if let Some(previous) = seen.as_ref() {
        for note in notes {
            let Some(id) = note["id"].as_str() else { continue };
            let title = note["title"].as_str().unwrap_or(id);
            let is_new = !previous.contains_key(id);
            let review = review_of(note);
            let (heading, show) = if review.as_deref() == Some("pending")
                && previous.get(id).map_or(true, |s| s.review.as_deref() != Some("pending"))
            {
                ("Plan por revisar", true)
            } else {
                let by_agent = note["meta"]["source"].as_str().map_or(false, |s| s != "user");
                ("Nueva nota", is_new && by_agent && note["meta"]["status"] == "unread")
            };
            if show {
                let _ = app.notification().builder().title(heading).body(title).show();
            }
        }
    }
    *seen = Some(current);
}

#[tauri::command]
fn render(markdown: String) -> String {
    markdown::render(&markdown)
}

// MARK: - Writing (all through the CLI)

#[tauri::command]
fn set_status(id: String, status: String) -> Result<(), String> {
    cli::run(&["set", &id, "--status", &status]).map(|_| ())
}

#[tauri::command]
fn set_pinned(id: String, pinned: bool) -> Result<(), String> {
    cli::run(&["set", &id, if pinned { "--pin" } else { "--no-pin" }]).map(|_| ())
}

#[tauri::command]
fn review(id: String, status: String, comment: Option<String>) -> Result<(), String> {
    let mut args = vec!["review", &id, &status];
    let comment = comment.unwrap_or_default();
    if !comment.trim().is_empty() {
        args.extend(["--comment", &comment]);
    }
    cli::run(&args).map(|_| ())
}

#[tauri::command]
fn check(id: String, task: String) -> Result<(), String> {
    cli::run(&["check", &id, &task]).map(|_| ())
}

#[tauri::command]
fn trash(id: String) -> Result<(), String> {
    cli::run(&["trash", &id]).map(|_| ())
}

#[tauri::command]
fn add_note(folder: String, title: String, body: String) -> Result<String, String> {
    let out = cli::run(&["add", &folder, "--title", &title, "--source", "user", "--no-topic", "--body", &body])?;
    Ok(out.trim().to_string())
}

// MARK: - Opening things

#[tauri::command]
fn open_url(app: AppHandle, url: String) -> Result<(), String> {
    if !(url.starts_with("https://") || url.starts_with("http://") || url.starts_with("mailto:")) {
        return Err("Solo se abren enlaces web".into());
    }
    app.opener().open_url(url, None::<&str>).map_err(|e| e.to_string())
}

#[tauri::command]
fn open_path(app: AppHandle, path: String) -> Result<(), String> {
    app.opener().open_path(path, None::<&str>).map_err(|e| e.to_string())
}

#[tauri::command]
fn reveal(app: AppHandle, path: String) -> Result<(), String> {
    app.opener().reveal_item_in_dir(path).map_err(|e| e.to_string())
}

// MARK: - Settings

#[tauri::command]
fn settings(app: AppHandle, state: tauri::State<AppState>) -> Value {
    json!({
        "version": app.package_info().version.to_string(),
        "root": cli::run(&["root"]).map(|r| r.trim().to_string()).unwrap_or_default(),
        "autostart": app.autolaunch().is_enabled().unwrap_or(false),
        "integrations": cli::json(&["setup", "--status", "--json"]).map(|v| v["integrations"].clone()).unwrap_or(Value::Null),
        "errors": *state.setup_errors.lock().unwrap(),
    })
}

#[tauri::command]
fn set_autostart(app: AppHandle, on: bool) -> Result<(), String> {
    let launcher = app.autolaunch();
    if on { launcher.enable() } else { launcher.disable() }.map_err(|e| e.to_string())?;
    sync_autostart_item(&app);
    Ok(())
}

/// Installs everything again, including what only the first launch sets up.
#[tauri::command]
fn reinstall(app: AppHandle, state: tauri::State<AppState>) -> Value {
    let marker = setup_marker(&app);
    let _ = std::fs::remove_file(&marker);
    *state.setup_errors.lock().unwrap() = system::set_up(&marker);
    settings(app, state)
}

#[tauri::command]
fn hide(app: AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

// MARK: - Window and tray

fn setup_marker(app: &AppHandle) -> PathBuf {
    app.path().app_config_dir().unwrap_or_else(|_| std::env::temp_dir()).join("setup-done")
}

fn show(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.move_window(Position::TrayBottomRight).or_else(|_| window.move_window(Position::BottomRight));
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn toggle(app: &AppHandle) {
    match app.get_webview_window("main") {
        Some(window) if window.is_visible().unwrap_or(false) => {
            let _ = window.hide();
        }
        _ => show(app),
    }
}

const AUTOSTART_ID: &str = "autostart";

/// The tray menu's checkmark follows the setting, whichever side changed it.
fn sync_autostart_item(app: &AppHandle) {
    if let Some(tray) = app.state::<AppState>().tray.lock().unwrap().as_ref() {
        let _ = tray.set_menu(tray_menu(app).ok());
    }
}

fn tray_menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let autostart = app.autolaunch().is_enabled().unwrap_or(false);
    Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "open", "Abrir coTs", true, None::<&str>)?,
            &MenuItem::with_id(app, "new", "Nueva nota", true, None::<&str>)?,
            &MenuItem::with_id(app, "folder", "Abrir carpeta de notas", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &CheckMenuItem::with_id(app, AUTOSTART_ID, "Abrir al iniciar sesión", true, autostart, None::<&str>)?,
            &MenuItem::with_id(app, "settings", "Ajustes…", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "quit", "Salir de coTs", true, None::<&str>)?,
        ],
    )
}

fn on_menu(app: &AppHandle, id: &str) {
    match id {
        "open" => show(app),
        "new" | "settings" => {
            show(app);
            let _ = app.emit(if id == "new" { "new-note" } else { "open-settings" }, ());
        }
        "folder" => {
            if let Ok(root) = cli::run(&["root"]) {
                let _ = app.opener().open_path(root.trim(), None::<&str>);
            }
        }
        AUTOSTART_ID => {
            let on = !app.autolaunch().is_enabled().unwrap_or(false);
            let _ = set_autostart(app.clone(), on);
        }
        "quit" => app.exit(0),
        _ => {}
    }
}

fn main() {
    // The uninstaller runs `coTsApp.exe --uninstall` before deleting the files.
    if std::env::args().any(|a| a == "--uninstall") {
        system::tear_down();
        return;
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show(app)))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_positioner::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            load, render, set_status, set_pinned, review, check, trash, add_note,
            open_url, open_path, reveal, settings, set_autostart, reinstall, hide
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            let tray = TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().cloned().ok_or("sin icono")?)
                .tooltip("coTs")
                .menu(&tray_menu(&handle)?)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| on_menu(app, event.id().as_ref()))
                .on_tray_icon_event(|tray, event| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        toggle(tray.app_handle());
                    }
                })
                .build(app)?;
            *app.state::<AppState>().tray.lock().unwrap() = Some(tray);
            if cfg!(debug_assertions) {
                show(&handle); // Development: no hunting for the tray icon.
            }

            // Agents' setup and the watcher need the CLI; neither should delay the tray.
            std::thread::spawn(move || {
                let errors = system::set_up(&setup_marker(&handle));
                *handle.state::<AppState>().setup_errors.lock().unwrap() = errors;
                if let Ok(root) = cli::run(&["root"]) {
                    let _ = watch::start(handle.clone(), PathBuf::from(root.trim()));
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| match event {
            // Like the macOS popover: closing or clicking elsewhere only hides it.
            WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = window.hide();
            }
            WindowEvent::Focused(false) => {
                if !cfg!(debug_assertions) {
                    let _ = window.hide();
                }
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("coTs no pudo arrancar");
}
