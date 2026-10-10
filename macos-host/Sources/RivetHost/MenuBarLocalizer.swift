import AppKit

/// The menu-bar titles SwiftUI seeds for the system menus ("File", "Edit",
/// "View", "Window", "Help") come from AppKit's English template: taskly
/// declares no bundle localizations, so those five never follow the app's
/// language setting while our CommandMenus (视图/设置) do — the stable mixed
/// bar. SwiftUI can neither retitle nor remove a system menu, so we re-apply
/// titles from the i18n table and prune the two menus PRODUCT-SPEC §8 does
/// not define (Edit, and the system View — our localized 视图 CommandMenu
/// *is* the spec's View menu).
///
/// Matching is by both the English seed titles and their zh renders so the
/// walk is language-independent: i18n starts at zh before settings land, so
/// an English launch meets 文件-titled menus on its first pass. The menu bar
/// renders a submenu item from the SUBMENU's title — retitle both or the
/// change never reaches the screen. SwiftUI resyncs reset titles and re-add
/// pruned menus without a hookable notification, hence the notifications +
/// slow self-healing pulse; apply() is idempotent and touches ~7 items.
@MainActor
enum MenuBarLocalizer {
    private static var installed = false

    /// System menu → i18n key. Both the AppKit English seed and the zh
    /// render are match candidates (i18n defaults to zh before settings).
    private static let candidates: [(key: String, titles: Set<String>)] = [
        ("menuFile", ["File", "文件"]),
        ("menuEdit", ["Edit", "编辑"]),
        ("menuView", ["View", "视图"]),
        ("menuWindow", ["Window", "窗口"]),
        ("menuHelp", ["Help", "帮助"]),
    ]

    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { apply() }
        }
        NotificationCenter.default.addObserver(
            forName: NSMenu.didChangeItemNotification,
            object: nil, queue: .main
        ) { _ in
            // apply() re-walks the whole bar, so the notification payload
            // (non-Sendable) is deliberately unused here.
            MainActor.assumeIsolated { apply() }
        }
        let pulse = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { apply() }
        }
        RunLoop.main.add(pulse, forMode: .common)
    }

    static func apply() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let i18n = I18nService.shared
        var prune: [NSMenuItem] = []
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            guard let candidate = candidates.first(where: { $0.titles.contains(item.title) })
            else { continue }
            if candidate.key == "menuEdit" {
                // §8 defines no Edit menu; text commands keep working through
                // the responder chain without it.
                prune.append(item)
                continue
            }
            if candidate.key == "menuView" {
                // Keep our own View menu — it carries the smart-view items.
                // The system one only holds Full Screen noise. The content
                // guard matters when the app language is English and both
                // are titled "View".
                let ours = submenu.items.contains { $0.title == i18n.t("navToday") }
                if !ours {
                    prune.append(item)
                }
                continue
            }
            let localized = i18n.t(candidate.key)
            item.title = localized
            submenu.title = localized
        }
        for item in prune where mainMenu.index(of: item) >= 0 {
            mainMenu.removeItem(item)
        }
    }
}
