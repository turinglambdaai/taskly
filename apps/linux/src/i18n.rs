//! i18n: zh/en tables from JSON files compiled into the binary
//! (byte-identical copies of shared/i18n/*.json — CI-verified single source).

use std::collections::HashMap;
use std::sync::Mutex;

const ZH_JSON: &str = include_str!("../resources/i18n/zh.json");
const EN_JSON: &str = include_str!("../resources/i18n/en.json");

pub struct I18n {
    tables: HashMap<&'static str, HashMap<String, String>>,
    current: Mutex<String>,
}

impl I18n {
    pub fn new() -> Self {
        let mut tables = HashMap::new();
        tables.insert("zh", load_table(ZH_JSON));
        tables.insert("en", load_table(EN_JSON));
        Self { tables, current: Mutex::new("zh".to_string()) }
    }

    pub fn from_language(lang: &str) -> Self {
        let i18n = Self::new();
        i18n.set_language(lang);
        i18n
    }

    /// "zh" | "en"; anything else falls back to zh.
    pub fn set_language(&self, lang: &str) {
        let normalized = if lang.eq_ignore_ascii_case("en") { "en" } else { "zh" };
        *self.current.lock().expect("i18n lock") = normalized.to_string();
    }

    pub fn language(&self) -> String {
        self.current.lock().expect("i18n lock").clone()
    }

    /// current → zh fallback → key itself.
    pub fn t(&self, key: &str) -> String {
        let current = self.current.lock().expect("i18n lock");
        if let Some(value) = self.tables.get(current.as_str()).and_then(|t| t.get(key)) {
            return value.clone();
        }
        if let Some(value) = self.tables.get("zh").and_then(|t| t.get(key)) {
            return value.clone();
        }
        key.to_string()
    }

    /// Positional {0}, {1} … placeholders.
    pub fn format(&self, key: &str, args: &[&str]) -> String {
        let mut text = self.t(key);
        for (index, arg) in args.iter().enumerate() {
            text = text.replace(&format!("{{{index}}}"), arg);
        }
        text
    }
}

fn load_table(json: &str) -> HashMap<String, String> {
    serde_json::from_str(json).unwrap_or_default()
}

impl Default for I18n {
    fn default() -> Self {
        Self::new()
    }
}
