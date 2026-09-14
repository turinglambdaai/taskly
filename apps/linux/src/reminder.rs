//! Due-task reminders (PRODUCT-SPEC §9): 60 s poll + startup check,
//! per-session dedupe, ≤3 individual / >3 aggregated. Transport = the
//! desktop notification daemon via `notify-send` (same fallback as 0.6.x).
//! Failures disable notifications for the session — never crash.

use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use chrono::NaiveDateTime;

use crate::date_parser::{DateParser, FULL_FORMAT};
use crate::db::SQLiteDatabase;
use crate::i18n::I18n;

pub struct ReminderService {
    db: Arc<SQLiteDatabase>,
    i18n: Arc<I18n>,
    notified_ids: Mutex<std::collections::HashSet<i64>>,
    native_disabled: Arc<AtomicBool>,
}

impl ReminderService {
    pub fn new(db: Arc<SQLiteDatabase>, i18n: Arc<I18n>) -> Self {
        Self {
            db,
            i18n,
            notified_ids: Mutex::new(std::collections::HashSet::new()),
            native_disabled: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn reset_notified(&self) {
        self.notified_ids.lock().expect("reminder lock").clear();
        self.native_disabled.store(false, Ordering::SeqCst);
    }

    pub fn check_now(&self) {
        let tasks = match self.db.get_all_incomplete_tasks_with_due_date() {
            Ok(tasks) => tasks,
            Err(_) => return,
        };

        let mut due: Vec<_> = tasks
            .into_iter()
            .filter(|t| is_due(t))
            .filter(|t| self.notified_ids.lock().expect("reminder lock").insert(t.id))
            .collect();
        if due.is_empty() {
            return;
        }

        if self.native_disabled.load(Ordering::SeqCst) {
            return;
        }

        if due.len() > 3 {
            let summary = self.i18n.format("reminderStartupSummary", &[&due.len().to_string()]);
            self.notify(&self.i18n.t("reminderTitle"), &summary);
        } else {
            due.sort_by_key(|t| t.id);
            for task in due {
                let due_line = match &task.due_time {
                    Some(time) if !time.is_empty() => format!("{} {time}", task.due_date.clone().unwrap_or_default()),
                    _ => task.due_date.clone().unwrap_or_default(),
                };
                let body = format!(
                    "{}\n{}: {due_line}",
                    task.text,
                    self.i18n.t("reminderDueAt")
                );
                self.notify(&self.i18n.t("reminderTitle"), &body);
            }
        }
    }

    fn notify(&self, title: &str, body: &str) {
        let result = Command::new("notify-send")
            .arg("--app-name=Taskly")
            .arg("--expire-time=10000")
            .arg(escape(title))
            .arg(escape(body))
            .status();

        if result.is_err() {
            // No notification daemon available: stay silent this session.
            self.native_disabled.store(true, Ordering::SeqCst);
        }
    }
}

fn escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn is_due(task: &crate::models::TaskItem) -> bool {
    let Some(due_date) = &task.due_date else { return false };
    let combined = DateParser::combine_datetime(Some(due_date), task.due_time.as_ref());
    match NaiveDateTime::parse_from_str(&combined, FULL_FORMAT) {
        Ok(due) => due <= chrono::Local::now().naive_local(),
        Err(_) => false,
    }
}
