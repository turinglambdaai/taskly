import Foundation

/// Bilingual string service. Strings come from the staged res/i18n JSON
/// files (byte-identical to shared/i18n/{zh,en}.json, staged by the release
/// pipeline). Lookup: current language → zh fallback → key
/// itself. `{0}` placeholders are formatted positionally.
final class I18nService: @unchecked Sendable {
    static let shared = I18nService()

    private var tables: [String: [String: String]] = [:] // lang → key → text
    private var current = "zh"
    private let lock = NSLock()

    /// Observers invoked (on the caller's thread) after a language switch.
    var onLanguageChanged: (@Sendable () -> Void)?

    private init() {
        tables["zh"] = Self.loadTable("zh")
        tables["en"] = Self.loadTable("en")
    }

    var language: String {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// "zh" | "en"; anything else falls back to zh.
    func setLanguage(_ lang: String) {
        let normalized = (lang.lowercased() == "en") ? "en" : "zh"
        var changed = false
        lock.lock()
        if normalized != current {
            current = normalized
            changed = true
        }
        lock.unlock()
        if changed {
            onLanguageChanged?()
        }
    }

    func t(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let v = tables[current]?[key] { return v }
        if let v = tables["zh"]?[key] { return v }
        return key
    }

    /// Positional formatting: first argument replaces {0}, etc.
    func format(_ key: String, _ args: Any...) -> String {
        var text = t(key)
        for (index, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(index)}", with: String(describing: arg))
        }
        return text
    }

    // MARK: - Resource loading

    private static func loadTable(_ lang: String) -> [String: String] {
        // Staged product resource (Contents/Resources/res in the .app,
        // <stage>/res or the dev tree otherwise) — same mechanism on all
        // three platforms; see HostResources.
        if let url = HostResources.locate(i18n: lang),
           let data = try? Data(contentsOf: url),
           let table = try? JSONDecoder().decode([String: String].self, from: data) {
            return table
        }
        return [:]
    }
}
