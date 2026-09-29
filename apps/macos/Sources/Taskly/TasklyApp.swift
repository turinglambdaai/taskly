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
        .defaultSize(width: 1280, height: 880)
        .commands {
            TasklyCommands(state: appState)
            // Strip system-injected noise that is outside PRODUCT-SPEC §8:
            // toolbar/sidebar/tab-bar groups (which otherwise spawn a second
            // View menu), text-editing extras (AutoFill/Dictation), and the
            // dead "Taskly Help" placeholder.
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            // Window-menu extras (Fill/Center/Move & Resize/Full Screen Tile)
            // and File save-group commands are outside PRODUCT-SPEC §8.
            CommandGroup(replacing: .windowArrangement) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .help) {
                Button(appState.t("menuAbout")) {
                    appState.aboutVisible = true
                }
            }
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
        }
        // Close lives in the save/close group: a replaced group must not be
        // empty — SwiftUI re-seeds empty groups' boundary separators on every
        // menu resync. This also displaces the system Close/Close All, whose
        // plain Cmd+W collided with Close Database.
        CommandGroup(replacing: .saveItem) {
            Button(state.t("menuCloseDatabase")) { confirmClose() }
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
