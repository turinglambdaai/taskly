import Foundation

/// Bilingual string service. Strings come from bundled JSON files that are
/// byte-identical copies of shared/i18n/{zh,en}.json (CI-verified).
/// Lookup: current language → zh fallback → key itself. `{0}` placeholders
/// are formatted positionally. Language changes notify observers so the UI
/// refreshes live.
public final class I18nService: @unchecked Sendable {
    public static let shared = I18nService()

    private var tables: [String: [String: String]] = [:] // lang → key → text
    private var current: String = "zh"
    private let lock = NSLock()

    /// Observers invoked (on the caller's thread) after a language switch.
    public var onLanguageChanged: (@Sendable () -> Void)?

    private init() {
        tables["zh"] = Self.loadTable("zh")
        tables["en"] = Self.loadTable("en")
    }

    public var language: String {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// "zh" | "en"; anything else falls back to zh.
    public func setLanguage(_ lang: String) {
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

    public func t(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let v = tables[current]?[key] { return v }
        if let v = tables["zh"]?[key] { return v }
        return key
    }

    /// Positional formatting: first argument replaces {0}, etc.
    public func format(_ key: String, _ args: Any...) -> String {
        var text = t(key)
        for (index, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(index)}", with: String(describing: arg))
        }
        return text
    }

    // MARK: - Resource loading

    private static func loadTable(_ lang: String) -> [String: String] {
        // Prefer the bundle copy (works for SPM dev runs and the .app).
        let bundle = Bundle.module
        if let url = bundle.url(forResource: lang, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let table = try? JSONDecoder().decode([String: String].self, from: data) {
            return table
        }
        return [:]
    }
}
