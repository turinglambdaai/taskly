//! CLI engine (contract: shared/spec/CLI-SPEC.md). Same argv contract, JSON
//! shapes, and exit codes as the macOS/Windows ports. The GUI layer is never
//! initialized on this path.

use std::cmp::min;
use std::io::Write;

use serde_json::json;

use crate::config::Config;
use crate::date_parser::{parse_due, DateParser};
use crate::db::{ListRepository, SQLiteDatabase, TaskRepository};
use crate::i18n::I18n;
use crate::models::{argb, AppError, AppErrorType, TaskItem, TaskViewType, TodoList};

/// Per-invocation context: opened DB + repositories.
pub struct CliContext {
    pub db: std::sync::Arc<SQLiteDatabase>,
    pub tasks: TaskRepository,
    pub lists: ListRepository,
    pub date_parser: DateParser,
    pub i18n: std::sync::Arc<I18n>,
    pub json: bool,
    pub quiet: bool,
}

impl CliContext {
    pub fn create(command: &str, db_path: Option<&str>, json: bool, quiet: bool) -> Result<Self, AppError> {
        let i18n = std::sync::Arc::new(I18n::new());

        if matches!(command, "install-cli" | "uninstall-cli" | "--help" | "-h" | "help") {
            let db = std::sync::Arc::new(SQLiteDatabase::new());
            return Ok(Self::build(db, i18n, json, quiet));
        }

        let db = std::sync::Arc::new(SQLiteDatabase::new());
        match db_path {
            Some(path) => db.set_database_path(path),
            None => {
                let config = Config::load();
                if let Some(last) = config.last_db_path() {
                    db.set_database_path(last);
                }
            }
        }

        db.ensure_connected().map_err(|err| {
            AppError::new(
                format!("Cannot open database: {} ({err})", db.database_path().display()),
                AppErrorType::Database,
            )
        })?;

        Ok(Self::build(db, i18n, json, quiet))
    }

    fn build(db: std::sync::Arc<SQLiteDatabase>, i18n: std::sync::Arc<I18n>, json: bool, quiet: bool) -> Self {
        let tasks = TaskRepository::new(std::sync::Arc::clone(&db), std::sync::Arc::clone(&i18n));
        let lists = ListRepository::new(std::sync::Arc::clone(&db), std::sync::Arc::clone(&i18n));
        Self { db, tasks, lists, date_parser: DateParser::new(), i18n, json, quiet }
    }
}

/// Entry point: returns the process exit code.
pub fn run(args: &[String]) -> i32 {
    let mut json = false;
    let mut quiet = false;
    let mut db_path: Option<String> = None;
    let mut rest: Vec<String> = vec![];
    let mut parse_error: Option<AppError> = None;

    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--json" => json = true,
            "--quiet" | "-q" => quiet = true,
            "--db" => {
                if index + 1 < args.len() {
                    index += 1;
                    db_path = Some(args[index].clone());
                } else {
                    parse_error = Some(AppError::new("Missing value for --db", AppErrorType::Validation));
                }
            }
            other => rest.push(other.to_string()),
        }
        index += 1;
    }

    if let Some(err) = parse_error {
        return fail(&err.message, err.exit_code());
    }

    let Some(command) = rest.first().cloned() else {
        return fail(
            "Usage: taskly <command> [options]\nCommands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli",
            1,
        );
    };

    let tail: Vec<String> = rest[1..].to_vec();

    let result = (|| -> Result<i32, AppError> {
        match command.as_str() {
            "list" => cmd_list(&command, &tail, json, quiet),
            "lists" => cmd_lists(&command, json, quiet),
            "add" => cmd_add(&command, &tail, json, quiet),
            "update" => cmd_update(&command, &tail, json, quiet),
            "done" => cmd_done(&command, &tail, json, quiet, true),
            "undone" => cmd_done(&command, &tail, json, quiet, false),
            "rm" => cmd_rm(&command, &tail, json, quiet),
            "search" => cmd_search(&command, &tail, json, quiet),
            "mklist" => cmd_mklist(&command, &tail, json, quiet),
            "rmlist" => cmd_rmlist(&command, &tail, json, quiet),
            "install-cli" => Ok(crate::cli_installer::install()),
            "uninstall-cli" => Ok(crate::cli_installer::uninstall()),
            "--help" | "-h" | "help" => {
                println!("Taskly — task manager command-line interface (for AI agents & scripting)");
                println!("Commands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli");
                println!("Global options: --json, --db <path>, --quiet (-q)");
                Ok(0)
            }
            other => Err(AppError::new(format!("Unknown command: \"{other}\""), AppErrorType::Generic)),
        }
    })();

    match result {
        Ok(code) => code,
        Err(err) => fail(&err.message, err.exit_code()),
    }
}

fn fail(message: &str, exit_code: i32) -> i32 {
    let payload = json!({ "ok": false, "error": message, "exitCode": exit_code });
    let pretty = serde_json::to_string_pretty(&payload).unwrap_or_default();
    eprintln!("{pretty}");
    exit_code
}

// ---------------- options parsing ----------------

const VALUE_OPTIONS: &[&str] = &[
    "--list", "--view", "--status", "--limit", "--due", "--time", "--notes", "--icon", "--color", "--text",
];
const FLAG_OPTIONS: &[&str] = &["--clear-due", "--clear-time", "--clear-notes"];

#[derive(Default)]
struct Options {
    values: std::collections::HashMap<String, String>,
    flags: std::collections::HashSet<String>,
    positionals: Vec<String>,
}

impl Options {
    fn value(&self, name: &str) -> Option<&str> {
        self.values.get(name).map(String::as_str)
    }

    fn has(&self, name: &str) -> bool {
        self.flags.contains(name)
    }
}

fn parse_options(args: &[String]) -> Result<Options, AppError> {
    let mut options = Options::default();
    let mut index = 0;
    while index < args.len() {
        let token = &args[index];
        if token == "--" {
            options.positionals.extend(args[index + 1..].iter().cloned());
            break;
        }
        if token.starts_with("--") {
            let (name, inline) = match token.find('=') {
                Some(eq) => (&token[..eq], Some(token[eq + 1..].to_string())),
                None => (token.as_str(), None),
            };
            if VALUE_OPTIONS.contains(&name) {
                if let Some(value) = inline {
                    options.values.insert(name.to_string(), value);
                } else if index + 1 < args.len() {
                    index += 1;
                    options.values.insert(name.to_string(), args[index].clone());
                } else {
                    return Err(AppError::new(format!("Missing value for {name}"), AppErrorType::Validation));
                }
            } else if FLAG_OPTIONS.contains(&name) {
                options.flags.insert(name.to_string());
            } else {
                return Err(AppError::new(format!("Unknown option: {name}"), AppErrorType::Validation));
            }
        } else if token.starts_with('-') && token.len() > 1 {
            return Err(AppError::new(format!("Unknown option: {token}"), AppErrorType::Validation));
        } else {
            options.positionals.push(token.clone());
        }
        index += 1;
    }
    Ok(options)
}

fn require_positional<'a>(options: &'a Options, index: usize, what: &str) -> Result<&'a str, AppError> {
    options.positionals.get(index).map(String::as_str).ok_or_else(|| {
        AppError::new(format!("Missing required argument: <{what}>"), AppErrorType::Validation)
    })
}

fn parse_int(s: &str, what: &str) -> Result<i64, AppError> {
    s.parse::<i64>().map_err(|_| {
        AppError::new(format!("Invalid {what}: \"{s}\""), AppErrorType::Validation)
    })
}

fn resolve_list_id(ctx: &CliContext, list: &str) -> Result<i64, AppError> {
    if let Ok(id) = list.parse::<i64>() {
        return Ok(id);
    }
    ctx.db
        .get_list_by_name(list)?
        .map(|l| l.id)
        .ok_or_else(|| AppError::new(format!("List not found by name: \"{list}\""), AppErrorType::NotFound))
}

fn parse_color(color: &str) -> Result<i32, AppError> {
    if let Ok(argb_int) = color.parse::<i32>() {
        return Ok(argb_int);
    }
    let hex = color.strip_prefix('#').ok_or_else(|| {
        AppError::new(format!("Invalid color: \"{color}\". Use #RRGGBB hex or ARGB int"), AppErrorType::Validation)
    })?;
    match hex.len() {
        6 => {
            let rgb = u32::from_str_radix(hex, 16).map_err(|_| {
                AppError::new(format!("Invalid hex color: \"{color}\". Use #RRGGBB (6) or #AARRGGBB (8)"), AppErrorType::Validation)
            })?;
            Ok(argb::from_hex(0xFF00_0000 | rgb))
        }
        8 => {
            let value = u32::from_str_radix(hex, 16).map_err(|_| {
                AppError::new(format!("Invalid hex color: \"{color}\". Use #RRGGBB (6) or #AARRGGBB (8)"), AppErrorType::Validation)
            })?;
            Ok(argb::from_hex(value))
        }
        _ => Err(AppError::new(
            format!("Invalid hex color: \"{color}\". Use #RRGGBB (6) or #AARRGGBB (8)"),
            AppErrorType::Validation,
        )),
    }
}

// ---------------- output ----------------

fn task_json(t: &TaskItem) -> serde_json::Value {
    json!({
        "id": t.id,
        "listId": t.list_id,
        "listName": t.list_name,
        "text": t.text,
        "completed": t.completed,
        "dueDate": t.due_date,
        "dueTime": t.due_time,
        "notes": t.notes,
        "createdAt": t.created_at,
    })
}

fn list_json(l: &TodoList) -> serde_json::Value {
    json!({
        "id": l.id,
        "name": l.name,
        "icon": l.icon,
        "color": l.color,
        "pendingCount": l.pending_count,
    })
}

fn print_json(value: &serde_json::Value) {
    println!("{}", serde_json::to_string_pretty(value).unwrap_or_default());
}

fn human_task_line(t: &TaskItem) -> String {
    let mark = if t.completed { "[x]" } else { "[ ]" };
    let due = match &t.due_date {
        Some(date) if !date.is_empty() => {
            let time_suffix = t.due_time.as_ref().map(|tm| format!(" {tm}")).unwrap_or_default();
            format!("  🗓 {date}{time_suffix}")
        }
        _ => String::new(),
    };
    format!("  {:>5}  {}  {}{}", t.id, mark, t.text, due)
}

fn print_task(ctx: &CliContext, t: &TaskItem) {
    if ctx.json {
        print_json(&task_json(t));
    } else if ctx.quiet {
        println!("{}", t.id);
    } else {
        println!("{}", human_task_line(t));
    }
}

fn print_tasks(ctx: &CliContext, tasks: &[TaskItem]) {
    if ctx.json {
        let array: Vec<serde_json::Value> = tasks.iter().map(task_json).collect();
        print_json(&serde_json::Value::Array(array));
        return;
    }
    if tasks.is_empty() {
        if !ctx.quiet {
            println!("(no tasks)");
        }
        return;
    }
    for t in tasks {
        print_task(ctx, t);
    }
}

fn print_lists(ctx: &CliContext, lists: &[TodoList]) {
    if ctx.json {
        let array: Vec<serde_json::Value> = lists.iter().map(list_json).collect();
        print_json(&serde_json::Value::Array(array));
        return;
    }
    for l in lists {
        let icon = l.icon.clone().unwrap_or_default();
        let icon = if icon.is_empty() { String::new() } else { format!("{icon} ") };
        println!("  {:>5}  {}{}  ({})", l.id, icon, l.name, l.pending_count);
    }
}

// ---------------- commands ----------------

fn open_ctx(command: &str, args: &[String], json: bool, quiet: bool) -> Result<CliContext, AppError> {
    // Pre-scan global flags out of tail (they may also appear in tail).
    let mut db_path: Option<String> = None;
    let mut filtered: Vec<String> = vec![];
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--json" => {}
            "--quiet" | "-q" => {}
            "--db" => {
                if index + 1 < args.len() {
                    index += 1;
                    db_path = Some(args[index].clone());
                }
            }
            other => filtered.push(other.to_string()),
        }
        index += 1;
    }
    let _ = filtered;
    CliContext::create(command, db_path.as_deref(), json, quiet)
}

fn cmd_list(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let list_arg = options.value("--list").map(String::from);
    let view_arg = options.value("--view").map(String::from);
    let status_arg = options.value("--status").unwrap_or("incomplete").to_string();
    let limit = parse_int(options.value("--limit").unwrap_or("1000"), "--limit")?;

    let view: TaskViewType;
    if let Some(list) = list_arg.filter(|s| !s.is_empty()) {
        view = TaskViewType::List(resolve_list_id(&ctx, &list)?);
    } else if view_arg.as_deref().unwrap_or("").is_empty() {
        view = TaskViewType::All;
    } else {
        view = match view_arg.as_deref().unwrap_or("").to_lowercase().as_str() {
            "today" => TaskViewType::Today,
            "planned" | "scheduled" => TaskViewType::Planned,
            "all" => TaskViewType::All,
            "completed" => TaskViewType::Completed,
            other => {
                return Err(AppError::new(
                    format!("Invalid --view: \"{other}\". Use today | planned | all | completed"),
                    AppErrorType::Validation,
                ))
            }
        };
    }

    let show_completed = match status_arg.to_lowercase().as_str() {
        "all" => true,
        "incomplete" | "open" | "pending" => false,
        "completed" | "done" => true,
        other => {
            return Err(AppError::new(
                format!("Invalid --status: \"{other}\". Use all | incomplete | completed"),
                AppErrorType::Validation,
            ))
        }
    };

    let tasks = ctx.tasks.get_tasks_by_view(view, limit, 0, show_completed)?;
    print_tasks(&ctx, &tasks);
    Ok(0)
}

fn cmd_lists(command: &str, json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, &[], json, quiet)?;
    let mut lists = ctx.db.get_all_lists()?;
    for list in lists.iter_mut() {
        list.pending_count = ctx.db.get_task_count_by_list(list.id).unwrap_or(0);
    }
    print_lists(&ctx, &lists);
    Ok(0)
}

fn cmd_add(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let text = require_positional(&options, 0, "text")?;
    let list_arg = options.value("--list").map(String::from);

    let list_id = match list_arg.filter(|s| !s.is_empty()) {
        Some(list) => resolve_list_id(&ctx, &list)?,
        None => ctx
            .lists
            .get_default_list()?
            .map(|l| l.id)
            .ok_or_else(|| {
                AppError::new(
                    "No lists exist yet. Create one with `taskly mklist` first.",
                    AppErrorType::NotFound,
                )
            })?,
    };

    let mut due_date: Option<String> = None;
    let mut due_time: Option<String> = None;
    if let Some(due) = options.value("--due").filter(|s| !s.is_empty()) {
        let (d, t) = parse_due(&ctx.date_parser, due)?;
        due_date = d;
        due_time = t;
    }
    if let Some(time) = options.value("--time").filter(|s| !s.is_empty()) {
        due_time = Some(time.to_string());
    }

    let task = TaskItem {
        id: 0,
        list_id,
        text: text.to_string(),
        created_at: crate::db::created_at_now(),
        due_date,
        due_time,
        completed: false,
        notes: options.value("--notes").map(String::from),
        list_name: None,
    };
    let id = ctx.tasks.add_task(&task)?;
    let mut task = task;
    task.id = id;
    print_task(&ctx, &task);
    Ok(0)
}

fn cmd_update(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let id_string = require_positional(&options, 0, "id")?;
    let id = parse_int(id_string, "id")?;

    let mut task = ctx
        .db
        .get_task_by_id(id)?
        .ok_or_else(|| AppError::new(format!("Task not found: {id}"), AppErrorType::NotFound))?;

    if let Some(text) = options.value("--text") {
        task.text = text.to_string();
    }

    if options.has("--clear-due") {
        task.due_date = None;
    } else if let Some(due) = options.value("--due") {
        let (d, t) = parse_due(&ctx.date_parser, due)?;
        task.due_date = d;
        if t.is_some() {
            task.due_time = t;
        }
    }

    if options.has("--clear-time") {
        task.due_time = None;
    } else if let Some(time) = options.value("--time") {
        task.due_time = Some(time.to_string());
    }

    if let Some(list) = options.value("--list") {
        task.list_id = resolve_list_id(&ctx, list)?;
    }

    if options.has("--clear-notes") {
        task.notes = None;
    } else if let Some(notes) = options.value("--notes") {
        task.notes = Some(notes.to_string());
    }

    ctx.tasks.update_task(&task)?;
    print_task(&ctx, &task);
    Ok(0)
}

fn cmd_done(command: &str, args: &[String], json: bool, quiet: bool, completed: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let id_string = require_positional(&options, 0, "id")?;
    let id = parse_int(id_string, "id")?;

    let affected = ctx.db.set_task_completed(id, completed)?;
    if affected == 0 {
        return Err(AppError::new(format!("Task not found: {id}"), AppErrorType::NotFound));
    }

    if ctx.json {
        if ctx.quiet {
            print_json(&json!({ "ok": true, "id": id, "completed": completed }));
        } else if let Some(task) = ctx.db.get_task_by_id(id)? {
            print_json(&task_json(&task));
        }
    } else if !ctx.quiet {
        if let Some(task) = ctx.db.get_task_by_id(id)? {
            println!("{}", human_task_line(&task));
        }
    }
    Ok(0)
}

fn cmd_rm(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let id_string = require_positional(&options, 0, "id")?;
    let id = parse_int(id_string, "id")?;

    let deleted = ctx.db.delete_task(id).map(|n| n > 0).unwrap_or(false);

    if ctx.json {
        print_json(&json!({ "ok": true, "id": id, "deleted": deleted }));
    } else if !ctx.quiet {
        println!("{}", if deleted { format!("Deleted task {id}") } else { format!("Task {id} did not exist") });
    }
    Ok(0)
}

fn cmd_search(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let keyword = require_positional(&options, 0, "keyword")?;
    let limit = parse_int(options.value("--limit").unwrap_or("100"), "--limit")? as usize;

    let results = ctx.tasks.search_tasks(keyword)?;
    let take = min(limit, results.len());
    print_tasks(&ctx, &results[..take]);
    Ok(0)
}

fn cmd_mklist(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let name = require_positional(&options, 0, "name")?;
    let icon = options.value("--icon").map(String::from);
    let color = match options.value("--color") {
        Some(c) => Some(parse_color(c)?),
        None => None,
    };

    let id = ctx.lists.add_list(name, icon.as_deref(), color)?;
    let created = ctx
        .db
        .get_list_by_id(id)?
        .unwrap_or_else(|| TodoList { id, name: name.to_string(), icon: icon.clone(), color, pending_count: 0 });

    if ctx.json {
        print_json(&list_json(&created));
    } else if ctx.quiet {
        println!("{id}");
    } else {
        let icon_text = created.icon.clone().unwrap_or_default();
        let icon_text = if icon_text.is_empty() { String::new() } else { format!("{icon_text} ") };
        println!("  {:>5}  {}{}  (0)", created.id, icon_text, created.name);
    }
    Ok(0)
}

fn cmd_rmlist(command: &str, args: &[String], json: bool, quiet: bool) -> Result<i32, AppError> {
    let ctx = open_ctx(command, args, json, quiet)?;
    let options = parse_options(args)?;
    let id_string = require_positional(&options, 0, "id")?;
    let id = parse_int(id_string, "id")?;

    let deleted = ctx.db.delete_list(id).map(|n| n > 0).unwrap_or(false);

    if ctx.json {
        print_json(&json!({ "ok": true, "id": id, "deleted": deleted }));
    } else if !ctx.quiet {
        println!(
            "{}",
            if deleted {
                format!("Deleted list {id} (and its tasks)")
            } else {
                format!("List {id} did not exist")
            }
        );
    }
    Ok(0)
}
