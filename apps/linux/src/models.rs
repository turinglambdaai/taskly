//! Data model mirroring the tasks/lists tables (DATA-FORMAT.md, schema v4).

/// ARGB helpers: the DB stores list colors as signed 32-bit ARGB ints.
pub mod argb {
    /// Signed ARGB int from a 0xAARRGGBB value.
    pub fn from_hex(hex: u32) -> i32 {
        hex as i32
    }

    pub fn to_hex(value: i32) -> u32 {
        value as u32
    }

    pub fn rgba(value: Option<i32>) -> (f64, f64, f64, f64) {
        match value {
            None => (0.0, 0.0, 0.0, 0.0),
            Some(v) => {
                let hex = to_hex(v);
                (
                    f64::from(((hex >> 16) & 0xFF) as u8) / 255.0,
                    f64::from(((hex >> 8) & 0xFF) as u8) / 255.0,
                    f64::from((hex & 0xFF) as u8) / 255.0,
                    f64::from(((hex >> 24) & 0xFF) as u8) / 255.0,
                )
            }
        }
    }
}

pub const DEFAULT_LIST_ICON: &str = "📋";
/// ARGB 0xFFC15F3C (Crail) as signed int.
pub const DEFAULT_LIST_COLOR: i32 = argb::from_hex(0xFFC1_5F3C);

#[derive(Debug, Clone, PartialEq)]
pub struct TaskItem {
    pub id: i64,
    pub list_id: i64,
    pub text: String,
    /// ISO-8601 local timestamp (compat with .NET "o").
    pub created_at: String,
    /// "yyyy-MM-dd" or None.
    pub due_date: Option<String>,
    /// "HH:mm" or None.
    pub due_time: Option<String>,
    pub completed: bool,
    pub notes: Option<String>,
    /// Join artifact; never persisted.
    pub list_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TodoList {
    pub id: i64,
    pub name: String,
    pub icon: Option<String>,
    /// Signed ARGB int or None.
    pub color: Option<i32>,
    /// Unfinished count, UI-only.
    pub pending_count: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskViewType {
    All,
    Today,
    Planned,
    Completed,
    List(i64),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppErrorType {
    Generic,
    Validation,
    NotFound,
    Database,
}

#[derive(Debug, Clone)]
pub struct AppError {
    pub message: String,
    pub error_type: AppErrorType,
}

impl AppError {
    pub fn new(message: impl Into<String>, error_type: AppErrorType) -> Self {
        Self { message: message.into(), error_type }
    }

    /// CLI exit code contract: generic→1, validation→2, notFound→3, db→4.
    pub fn exit_code(&self) -> i32 {
        match self.error_type {
            AppErrorType::Generic => 1,
            AppErrorType::Validation => 2,
            AppErrorType::NotFound => 3,
            AppErrorType::Database => 4,
        }
    }
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for AppError {}

pub type AppResult<T> = Result<T, AppError>;

/// Input validation limits (cross-platform contract).
pub mod validation {
    use super::{AppError, AppErrorType, AppResult};

    pub const MAX_TASK_TEXT_LENGTH: usize = 1000;
    pub const MAX_LIST_NAME_LENGTH: usize = 100;
    pub const MAX_SEARCH_KEYWORD_LENGTH: usize = 200;
    pub const MIN_YEAR: i32 = 1900;
    pub const MAX_YEAR: i32 = 2100;

    pub fn validate_task_text(text: &str, i18n: &crate::i18n::I18n) -> AppResult<()> {
        if text.trim().is_empty() {
            return Err(AppError::new(i18n.t("errorEnterTaskDesc"), AppErrorType::Validation));
        }
        if text.chars().count() > MAX_TASK_TEXT_LENGTH {
            return Err(AppError::new(
                i18n.format("errorTaskDescTooLong", &[&MAX_TASK_TEXT_LENGTH.to_string()]),
                AppErrorType::Validation,
            ));
        }
        Ok(())
    }

    pub fn validate_list_name(name: &str, i18n: &crate::i18n::I18n) -> AppResult<()> {
        if name.trim().is_empty() {
            return Err(AppError::new(i18n.t("errorEnterListName"), AppErrorType::Validation));
        }
        if name.chars().count() > MAX_LIST_NAME_LENGTH {
            return Err(AppError::new(
                i18n.format("errorListNameTooLong", &[&MAX_LIST_NAME_LENGTH.to_string()]),
                AppErrorType::Validation,
            ));
        }
        Ok(())
    }
}
