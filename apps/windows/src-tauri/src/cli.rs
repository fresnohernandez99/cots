//! The `cots` CLI shipped next to this app. Every read and write goes through it, so
//! notes written on Windows are byte for byte what the macOS app and the agents write.

use std::path::PathBuf;
use std::process::{Command, Output};

#[cfg(windows)]
const NAME: &str = "cots.exe";
#[cfg(not(windows))]
const NAME: &str = "cots";

/// Tauri copies the sidecar next to the main executable, both installed and in `tauri dev`.
pub fn path() -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let cli = exe.with_file_name(NAME);
    if cli.exists() {
        Ok(cli)
    } else {
        Err(format!("No encuentro {} junto a la app", cli.display()))
    }
}

pub fn command(args: &[&str]) -> Result<Command, String> {
    let mut cmd = Command::new(path()?);
    cmd.args(args);
    #[cfg(windows)]
    {
        // A console program would flash a black window on every call.
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    Ok(cmd)
}

/// Runs `cots <args>` and returns stdout, or stderr as the error the UI shows.
pub fn run(args: &[&str]) -> Result<String, String> {
    let output: Output = command(args)?.output().map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        let err = String::from_utf8_lossy(&output.stderr).trim().to_string();
        Err(if err.is_empty() { format!("cots {} falló", args.join(" ")) } else { err })
    }
}

pub fn json(args: &[&str]) -> Result<serde_json::Value, String> {
    serde_json::from_str(&run(args)?).map_err(|e| e.to_string())
}
