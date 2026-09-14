//! Natural-language date/time parser (contract: CLI-SPEC.md §--due).
//! Faithful port of DateParser.cs grammar:
//!   +N{m|h|d|w|M}  (case-sensitive m/M; digits optional = 1; M = 30 days)
//!   @now | @H[:MM][am|pm] [tomorrow|tmw|mon..sun]  (past time → tomorrow)
//!   yyyy-MM-dd / yyyy/MM/dd / MM/dd/yyyy / dd/MM/yyyy  (1900..=2100)

use chrono::{Datelike, Duration, Local, NaiveDate, NaiveDateTime, Timelike};

use crate::models::{validation, AppError, AppErrorType};

pub const FULL_FORMAT: &str = "%Y-%m-%d %H:%M:%S";
pub const DATE_FORMAT: &str = "%Y-%m-%d";
pub const TIME_FORMAT: &str = "%H:%M";

#[derive(Default)]
pub struct DateParser;

impl DateParser {
    pub fn new() -> Self {
        Self
    }

    /// Parses into `%Y-%m-%d %H:%M:%S` (relative/at) or `%Y-%m-%d` (absolute).
    pub fn parse(&self, input: &str) -> Option<String> {
        let s = input.trim();
        if s.is_empty() {
            return None;
        }

        if let Some(body) = s.strip_prefix('+') {
            return self.parse_relative(body);
        }

        if let Some(body) = s.strip_prefix('@') {
            return self.parse_at(body);
        }

        self.parse_absolute(s)
    }

    fn parse_relative(&self, body: &str) -> Option<String> {
        // ^(\d*)([mhdwM])$
        let (digits, unit) = body.split_at(body.len().saturating_sub(1));
        let amount: i64 = if digits.is_empty() {
            1
        } else {
            digits.parse().ok()?
        };
        let now = Local::now().naive_local();
        let result = match unit {
            "m" => now + Duration::minutes(amount),
            "h" => now + Duration::hours(amount),
            "d" => now + Duration::days(amount),
            "w" => now + Duration::days(amount * 7),
            "M" => now + Duration::days(amount * 30),
            _ => return None,
        };
        Some(result.format(FULL_FORMAT).to_string())
    }

    fn parse_at(&self, body: &str) -> Option<String> {
        let trimmed = body.trim();
        if trimmed.eq_ignore_ascii_case("now") {
            return Some(Local::now().naive_local().format(FULL_FORMAT).to_string());
        }

        let mut parts = trimmed.splitn(2, ' ');
        let time_part = parts.next().unwrap_or("");
        let modifier = parts.next().filter(|m| !m.is_empty());

        // ^(\d{1,2})(?::(\d{2}))?(am|pm)?$ (case-insensitive)
        let (core, ampm) = {
            let lower = time_part.to_lowercase();
            if let Some(core) = lower.strip_suffix("am") {
                (core, Some(false))
            } else if let Some(core) = lower.strip_suffix("pm") {
                (core, Some(true))
            } else {
                (time_part, None)
            }
        };

        let (hour_str, min_str) = match core.split_once(':') {
            Some((h, m)) => (h, m),
            None => (core, ""),
        };

        if hour_str.is_empty() || hour_str.len() > 2 || (!min_str.is_empty() && min_str.len() != 2) {
            return None;
        }
        if !min_str.is_empty() && !min_str.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
        if !hour_str.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }

        let mut hour: u32 = hour_str.parse().ok()?;
        let minute: u32 = if min_str.is_empty() { 0 } else { min_str.parse().ok()? };

        match ampm {
            Some(false) => {
                if hour == 12 {
                    hour = 0;
                }
            }
            Some(true) => {
                if hour < 12 {
                    hour += 12;
                }
            }
            None => {}
        }

        if hour > 23 || minute > 59 {
            return None;
        }

        let now = Local::now().naive_local();
        let mut date = now
            .date()
            .and_hms_opt(hour, minute, 0)?;

        match modifier {
            Some(m) => date = self.apply_day_modifier(date, m),
            None => {
                if date < now {
                    date += Duration::days(1);
                }
            }
        }

        Some(date.format(FULL_FORMAT).to_string())
    }

    fn apply_day_modifier(&self, date: NaiveDateTime, modifier: &str) -> NaiveDateTime {
        let m = modifier.to_lowercase();
        if m == "tomorrow" || m == "tmw" {
            return date + Duration::days(1);
        }

        let target = match m.as_str() {
            "sun" => 0,
            "mon" => 1,
            "tue" => 2,
            "wed" => 3,
            "thu" => 4,
            "fri" => 5,
            "sat" => 6,
            _ => return date,
        };

        // chrono: Sunday = 0
        let current = date.weekday().num_days_from_sunday() as i64;
        let target = target as i64;
        let mut diff = (target - current + 7) % 7;
        if diff <= 0 {
            diff += 7;
        }
        date + Duration::days(diff)
    }

    fn parse_absolute(&self, input: &str) -> Option<String> {
        let s = input.trim();
        let formats = ["%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%d/%m/%Y"];

        for fmt in formats {
            if let Ok(date) = NaiveDate::parse_from_str(s, fmt) {
                if date.year() < validation::MIN_YEAR || date.year() > validation::MAX_YEAR {
                    return None;
                }
                return Some(date.format(DATE_FORMAT).to_string());
            }
        }

        None
    }

    /// Trailing @ command, then trailing relative command.
    pub fn extract_time_command(&self, input: &str) -> (String, Option<String>) {
        if input.trim().is_empty() {
            return (input.to_string(), None);
        }

        let mut text = input.to_string();
        let mut command: Option<String> = None;

        // Trailing @ command: @(now|H[:MM][am|pm])( tomorrow|tmw|mon..sun)?  (CI)
        let at_re = regex::Regex::new(
            r"(?i)@(?:now|\d{1,2}(?::\d{2})?(?:am|pm)?)(?:\s+(?:tomorrow|tmw|mon|tue|wed|thu|fri|sat|sun))?$",
        )
        .expect("valid regex");
        if let Some(found) = at_re.find(&text) {
            if let Some(at_index) = text.find('@') {
                command = Some(text[at_index..].trim().to_string());
                text = text[..at_index].trim_end().to_string();
            }
        }

        // Trailing relative: (?:^|\s)(\+\d+[mhdwM])(?:\s|$)
        let rel_re = regex::Regex::new(r"(?:^|\s)(\+\d+[mhdwM])(?:\s|$)").expect("valid regex");
        if let Some(caps) = rel_re.captures(&text) {
            let whole = caps.get(0).expect("group 0");
            command = Some(caps.get(1).expect("group 1").as_str().to_string());
            let start = whole.start();
            let end = whole.end();
            text = format!("{}{}", &text[..start], &text[end..]).trim().to_string();
        }

        (text.trim().to_string(), command)
    }

    /// First 10 chars ("yyyy-MM-dd").
    pub fn extract_date_only(s: Option<&String>) -> Option<String> {
        let s = s?;
        if s.is_empty() {
            return None;
        }
        Some(if s.len() >= 10 { s[..10].to_string() } else { s.to_string() })
    }

    /// chars [11..16] ("HH:mm") when present.
    pub fn extract_time_only(s: Option<&String>) -> Option<String> {
        let s = s?;
        if s.len() < 16 {
            return None;
        }
        Some(s[11..16].to_string())
    }

    /// date + time → "yyyy-MM-dd HH:mm:00" (defaults: today / 00:00).
    pub fn combine_datetime(date_str: Option<&String>, time_str: Option<&String>) -> String {
        let date = Self::extract_date_only(date_str)
            .unwrap_or_else(|| Local::now().format(DATE_FORMAT).to_string());
        let time = match time_str {
            Some(t) if !t.is_empty() => t.clone(),
            _ => "00:00".to_string(),
        };
        format!("{date} {time}:00")
    }

    /// "yyyy-MM-dd HH:mm:ss" → NaiveDateTime (local semantics).
    pub fn parse_full(s: &str) -> Option<NaiveDateTime> {
        NaiveDateTime::parse_from_str(s, FULL_FORMAT).ok()
    }
}

/// CLI --due wrapper: bare-word mapping + date-only intent rule.
pub fn parse_due(parser: &DateParser, due: &str) -> Result<(Option<String>, Option<String>), AppError> {
    let original = due.trim();
    let lower = original.to_lowercase();
    let normalized = match lower.as_str() {
        "today" => "+0d".to_string(),
        "tomorrow" | "tmw" => "+1d".to_string(),
        "tonight" => "@20:00".to_string(),
        _ => original.to_string(),
    };

    let parsed = parser.parse(&normalized).ok_or_else(|| {
        AppError::new(
            format!(
                "Cannot parse date/time: \"{due}\". Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd"
            ),
            AppErrorType::Validation,
        )
    })?;

    let mut date = DateParser::extract_date_only(Some(&parsed));
    let mut time = DateParser::extract_time_only(Some(&parsed));

    let is_date_only = lower == "today"
        || lower == "tomorrow"
        || lower == "tmw"
        || (normalized.starts_with('+')
            && matches!(normalized.chars().last(), Some('d') | Some('w') | Some('M')))
        || parsed.len() == 10;

    if is_date_only {
        time = None;
    }

    Ok((date, time))
}

/// ISO-8601 with local offset (compat with .NET "o" created_at).
pub fn created_at_now() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S%.6f%:z").to_string()
}

pub fn today_string() -> String {
    Local::now().format(DATE_FORMAT).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_and_absolute() {
        let parser = DateParser::new();
        assert!(parser.parse("+10m").is_some());
        assert!(parser.parse("+d").is_some(), "digits optional");
        assert!(parser.parse("+x").is_none());
        assert_eq!(parser.parse("2026-08-07").as_deref(), Some("2026-08-07"));
        assert_eq!(parser.parse("2026/08/07").as_deref(), Some("2026-08-07"));
        assert!(parser.parse("1899-12-31").is_none());
        assert!(parser.parse("2101-01-01").is_none());
    }

    #[test]
    fn extract_time_command() {
        let parser = DateParser::new();
        let (text, cmd) = parser.extract_time_command("买牛奶 @10am");
        assert_eq!(text, "买牛奶");
        assert_eq!(cmd.as_deref(), Some("@10am"));
        let (text2, cmd2) = parser.extract_time_command("交报告 +1d");
        assert_eq!(text2, "交报告");
        assert_eq!(cmd2.as_deref(), Some("+1d"));
    }

    #[test]
    fn combine() {
        assert_eq!(
            DateParser::combine_datetime(Some(&"2026-08-07".into()), Some(&"10:30".into())),
            "2026-08-07 10:30:00"
        );
    }
}
