using System.Text.Json;

namespace Taskly.Services;

/// <summary>
/// Bilingual string service. Strings come from Strings/{zh,en}.json —
/// byte-identical copies of shared/i18n (CI-verified single source).
/// Lookup: current language → zh fallback → key itself. Language switches
/// raise LanguageChanged so views refresh live.
/// </summary>
public sealed class I18nService
{
    public static I18nService Instance { get; } = new();

    public event Action? LanguageChanged;

    private readonly Dictionary<string, Dictionary<string, string>> _tables = new();
    private string _current = "zh";

    private I18nService()
    {
        _tables["zh"] = LoadTable("zh") ?? [];
        _tables["en"] = LoadTable("en") ?? [];
    }

    public string Current => _current;

    public void SetLanguage(string lang)
    {
        var normalized = lang.Equals("en", StringComparison.OrdinalIgnoreCase) ? "en" : "zh";
        if (normalized == _current)
        {
            return;
        }

        _current = normalized;
        LanguageChanged?.Invoke();
    }

    public string T(string key)
    {
        if (_tables[_current].TryGetValue(key, out var v))
        {
            return v;
        }

        if (_tables["zh"].TryGetValue(key, out var zh))
        {
            return zh;
        }

        return key;
    }

    public string Format(string key, params object[] args)
    {
        return string.Format(CultureInfo.InvariantCulture, T(key), args);
    }

    private static Dictionary<string, string>? LoadTable(string lang)
    {
        // {AppDir}/Strings/{lang}.json (Content item, PreserveNewest).
        var path = Path.Combine(AppContext.BaseDirectory, "Strings", $"{lang}.json");
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<Dictionary<string, string>>(json);
        }
        catch
        {
            return null;
        }
    }
}
