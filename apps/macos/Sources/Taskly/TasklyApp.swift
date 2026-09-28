import SwiftUI
import AppKit

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
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button(state.t("menuOpenDatabase")) { openDatabase() }
                .keyboardShortcut("o", modifiers: [.command])
            Button(state.t("menuCloseDatabase")) { confirmClose() }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!state.isConnected)
        }

        // View menu mirrors the Windows View menu: smart views, quick
        // add / search focus, show-completed toggle.
        CommandMenu(state.t("menuView")) {
            Button(state.t("navToday")) { state.select(.today) }
                .keyboardShortcut("1", modifiers: [.command])
            Button(state.t("navPlanned")) { state.select(.planned) }
                .keyboardShortcut("2", modifiers: [.command])
            Button(state.t("navAll")) { state.select(.all) }
                .keyboardShortcut("3", modifiers: [.command])
            Button(state.t("navCompleted")) { state.select(.completed) }
                .keyboardShortcut("4", modifiers: [.command])
            Divider()
            Button(newTaskMenuTitle) { state.quickAddFocusToken += 1 }
                .keyboardShortcut("n", modifiers: [.command])
            Button(state.t("searchHint")) { state.searchFocusToken += 1 }
                .keyboardShortcut("f", modifiers: [.command])
            Divider()
            Toggle(state.t("showCompletedToggle"), isOn: Binding(
                get: { state.showCompleted },
                set: {
                    state.showCompleted = $0
                    state.refresh()
                }))
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandMenu(state.t("menuTools")) {
            Button(state.t("menuInstallCli")) { state.installCli() }
            Button(state.t("menuUninstallCli")) { state.uninstallCli() }
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
        }

        CommandGroup(after: .appInfo) {
            Button(state.t("menuAbout")) {
                state.aboutVisible = true
            }
        }
    }

    /// Windows trims the "+ " prompt off the quick-add hint for the
    /// View-menu item; keep the same label ("添加任务" / "Add Task").
    private var newTaskMenuTitle: String {
        String(state.t("taskListInputHint").drop(while: { $0 == "+" || $0 == " " }))
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
