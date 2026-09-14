//! install-cli / uninstall-cli for macOS/Linux: shell wrapper at
//! ~/.local/bin/taskly + idempotent PATH block in ~/.zshrc (macOS) /
//! ~/.bashrc (Linux).

use std::fs;
use std::os::unix::fs::PermissionsExt;

use crate::config;

fn bin_dir() -> std::path::PathBuf {
    config::home_directory().join(".local/bin")
}

fn link_path() -> std::path::PathBuf {
    bin_dir().join("taskly")
}

fn executable_path() -> String {
    std::env::current_exe()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "taskly".to_string())
}

pub fn install() -> i32 {
    let exe = executable_path();
    let dir = bin_dir();
    let link = link_path();

    if let Err(err) = fs::create_dir_all(&dir) {
        eprintln!("Install failed: {err}");
        return 1;
    }

    let script = format!("#!/bin/sh\nexec \"{}\" \"$@\"\n", exe.replace('"', "\\\""));
    if let Err(err) = fs::write(&link, script) {
        eprintln!("Install failed: {err}");
        return 1;
    }
    if let Ok(metadata) = fs::metadata(&link) {
        let mut perms = metadata.permissions();
        perms.set_mode(0o755);
        let _ = fs::set_permissions(&link, perms);
    }

    let mut needs_restart = false;
    if !path_contains_bin_dir() {
        needs_restart = ensure_path_in_shell_rc();
    }

    println!("taskly command installed to {}", link.display());
    if needs_restart {
        println!("\nPlease open a new terminal window for the PATH change to take effect.");
    }
    0
}

pub fn uninstall() -> i32 {
    let link = link_path();
    if !link.exists() {
        eprintln!("taskly command was not installed (nothing to remove).");
        return 1;
    }
    if let Err(err) = fs::remove_file(&link) {
        eprintln!("Uninstall failed: {err}");
        return 1;
    }
    println!("taskly command removed from {}", link.display());
    0
}

fn path_contains_bin_dir() -> bool {
    std::env::var("PATH")
        .map(|path| path.split(':').any(|entry| entry == bin_dir().to_string_lossy()))
        .unwrap_or(false)
}

fn ensure_path_in_shell_rc() -> bool {
    let rc = config::home_directory().join(".zshrc");
    let marker = "# Added by Taskly";
    let content = fs::read_to_string(&rc).unwrap_or_default();
    if content.contains(marker) || content.contains(".local/bin") {
        return false;
    }

    let block = "\n# Added by Taskly\nexport PATH=\"$HOME/.local/bin:$PATH\"\n";
    let updated = if content.is_empty() || content.ends_with('\n') {
        format!("{content}{block}")
    } else {
        format!("{content}\n{block}")
    };
    fs::write(&rc, updated).is_ok()
}
