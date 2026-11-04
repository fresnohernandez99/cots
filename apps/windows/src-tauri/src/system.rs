//! Setting coTs up for agents, and undoing it. `cots setup` writes the skill, the
//! Claude Code hooks and the Claude Desktop MCP entry; this file adds what only the
//! Windows app can do: putting the install folder on the user's PATH so agents find `cots`.

use crate::cli;
use std::path::Path;

/// First launch installs everything; later launches refresh what's installed so it
/// points at this copy of the app. Returns the errors to show in Ajustes.
///
/// The marker holds the version that set things up. An update runs the old version's
/// uninstaller, which removes the integrations, so a new version counts as a first launch.
pub fn set_up(marker: &Path) -> Vec<String> {
    let version = env!("CARGO_PKG_VERSION");
    let first = std::fs::read_to_string(marker).map_or(true, |v| v.trim() != version);
    let mut errors = Vec::new();
    if let Err(e) = path::add() {
        errors.push(format!("PATH: {e}"));
    }
    let args: &[&str] = if first { &["setup", "--first-launch"] } else { &["setup"] };
    match cli::run(args) {
        Ok(_) => {
            if let Some(dir) = marker.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            let _ = std::fs::write(marker, version);
        }
        Err(e) => errors.extend(e.lines().map(str::to_string)),
    }
    errors
}

/// What `--uninstall` (run by the uninstaller) removes. Notes are never touched.
pub fn tear_down() {
    let _ = cli::run(&["setup", "--remove"]);
    let _ = path::remove();
}

#[cfg(windows)]
mod path {
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_EXPAND_SZ};
    use winreg::types::{FromRegValue, ToRegValue};
    use winreg::RegKey;

    fn install_dir() -> Result<String, String> {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        Ok(exe.parent().ok_or("sin carpeta")?.to_string_lossy().into_owned())
    }

    fn entries(path: &str) -> Vec<String> {
        path.split(';').filter(|p| !p.is_empty()).map(str::to_string).collect()
    }

    fn update(change: impl FnOnce(&mut Vec<String>) -> bool) -> Result<(), String> {
        let env = RegKey::predef(HKEY_CURRENT_USER)
            .open_subkey_with_flags("Environment", KEY_READ | KEY_WRITE)
            .map_err(|e| e.to_string())?;
        // Windows stores the user Path as REG_EXPAND_SZ with entries like
        // %USERPROFILE%\...\WindowsApps; writing it back as REG_SZ would stop those from
        // expanding. Keep the type, and never write anything after a failed read.
        let (current, vtype) = match env.get_raw_value("Path") {
            Ok(value) => (String::from_reg_value(&value).map_err(|e| e.to_string())?, value.vtype),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (String::new(), REG_EXPAND_SZ),
            Err(e) => return Err(e.to_string()),
        };
        let mut list = entries(&current);
        if change(&mut list) {
            let mut value = list.join(";").to_reg_value();
            value.vtype = vtype;
            env.set_raw_value("Path", &value).map_err(|e| e.to_string())?;
            broadcast();
        }
        Ok(())
    }

    pub fn add() -> Result<(), String> {
        let dir = install_dir()?;
        update(|list| {
            if list.iter().any(|p| p.eq_ignore_ascii_case(&dir)) {
                return false;
            }
            list.push(dir);
            true
        })
    }

    pub fn remove() -> Result<(), String> {
        let dir = install_dir()?;
        update(|list| {
            let before = list.len();
            list.retain(|p| !p.eq_ignore_ascii_case(&dir));
            list.len() != before
        })
    }

    /// Tells Explorer the environment changed, so terminals opened from now on see `cots`.
    fn broadcast() {
        use windows_sys::Win32::UI::WindowsAndMessaging::{
            SendMessageTimeoutW, HWND_BROADCAST, SMTO_ABORTIFHUNG, WM_SETTINGCHANGE,
        };
        let name: Vec<u16> = "Environment\0".encode_utf16().collect();
        unsafe {
            SendMessageTimeoutW(
                HWND_BROADCAST,
                WM_SETTINGCHANGE,
                0,
                name.as_ptr() as isize,
                SMTO_ABORTIFHUNG,
                2000,
                std::ptr::null_mut(),
            );
        }
    }
}

/// On macOS and Linux the app is only built for development; the PATH is left alone.
#[cfg(not(windows))]
mod path {
    pub fn add() -> Result<(), String> {
        Ok(())
    }
    pub fn remove() -> Result<(), String> {
        Ok(())
    }
}
