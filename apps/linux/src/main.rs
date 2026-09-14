//! Taskly entry point. Dual-mode contract: ANY argument routes to the CLI
//! before any GTK initialization (headless-safe); no arguments opens the GUI.

mod cli;
mod cli_installer;
mod config;
mod date_parser;
mod db;
mod dialogs;
mod i18n;
mod models;
mod reminder;
mod repositories_palette;
mod ui;
mod ui_ref;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if !args.is_empty() {
        let code = cli::run(&args);
        std::process::exit(code);
    }

    ui::run();
}
