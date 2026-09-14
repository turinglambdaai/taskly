import SwiftUI

/// Taskly macOS app. Entry logic lives in main.swift: CLI subcommands run
/// headless; no arguments opens this scene.
struct TasklyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Taskly") {
            MainWindowView()
                .environment(appState)
                .frame(
                    minWidth: 760, idealWidth: 1024,
                    minHeight: 520, idealHeight: 768)
        }
        .commands {
            TasklyCommands(state: appState)
        }
    }
}

/// Native menu bar (localized, live language switch).
struct TasklyCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(state.t("menuNewDatabase")) { newDatabase() }
                .keyboardShortcut("n", modifiers: [.command])
            Button(state.t("menuOpenDatabase")) { openDatabase() }
                .keyboardShortcut("o", modifiers: [.command])
            Button(state.t("menuCloseDatabase")) { confirmClose() }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!state.isConnected)
        }

        CommandMenu(state.t("menuSettings")) {
            Menu(state.t("menuLanguage")) {
                Button(state.t("menuLangZh")) {
                    setLanguage("zh")
                }
                .disabled(state.i18n.language == "zh")
                Button(state.t("menuLangEn")) {
                    setLanguage("en")
                }
                .disabled(state.i18n.language == "en")
            }
            Toggle(state.t("menuDarkMode"), isOn: Binding(
                get: { state.theme.isDark },
                set: { state.theme.isDark = $0 }))
            Divider()
            Button(state.t("menuInstallCli")) { state.installCli() }
            Button(state.t("menuUninstallCli")) { state.uninstallCli() }
        }

        CommandGroup(after: .appInfo) {
            Button(state.t("menuAbout")) {
                state.aboutVisible = true
            }
        }
    }

    private func setLanguage(_ language: String) {
        state.i18n.setLanguage(language)
        state.config.language = language
        state.config.save()
    }

    private func newDatabase() {
        let panel = NSSavePanel()
        panel.title = state.t("dialogSaveDbTitle")
        panel.nameFieldStringValue = "tasks"
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK, let url = panel.url {
            state.newDatabase(at: url)
        }
    }

    private func openDatabase() {
        let panel = NSOpenPanel()
        panel.title = state.t("dialogSelectDbFile")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK, let url = panel.url {
            state.openDatabase(at: url)
        }
    }

    private func confirmClose() {
        state.confirmContext = ConfirmContext(
            title: state.t("dialogConfirmCloseDb"),
            message: state.t("dialogConfirmCloseDbContent"),
            onConfirm: { state.closeDatabase() })
    }
}
