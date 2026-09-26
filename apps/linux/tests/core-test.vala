// Contract tests: date parser grammar, i18n flat-JSON parsing, CLI JSON
// escaping, database schema/round-trip. Run via `meson test`.

namespace Taskly.Tests {

int main(string[] args) {
    var failures = 0;
    failures += check("relative +10m", new DateParser().parse("+10m") != null);
    failures += check("relative +d (digits optional)", new DateParser().parse("+d") != null);
    failures += check("relative +x invalid", new DateParser().parse("+x") == null);
    failures += check("absolute iso", new DateParser().parse("2026-08-07") == "2026-08-07");
    failures += check("absolute slashed", new DateParser().parse("2026/08/07") == "2026-08-07");
    failures += check("absolute us", new DateParser().parse("08/07/2026") == "2026-08-07");
    failures += check("year low bound", new DateParser().parse("1899-12-31") == null);
    failures += check("year high bound", new DateParser().parse("2101-01-01") == null);
    failures += check("@now", new DateParser().parse("@now") != null);
    failures += check("@10:30pm", new DateParser().parse("@10:30pm") != null);
    failures += check("@25:00 invalid", new DateParser().parse("@25:00") == null);
    failures += check("@10am tomorrow", new DateParser().parse("@10am tomorrow") != null);

    var parser = new DateParser();
    var extracted = parser.extract_time_command("买牛奶 @10am");
    failures += check("extract text", extracted.text == "买牛奶");
    failures += check("extract @cmd", extracted.command != null && extracted.command.down() == "@10am");
    var extracted2 = parser.extract_time_command("交报告 +1d");
    failures += check("extract +cmd", extracted2.command == "+1d");

    try {
        var due = parse_due(parser, "today");
        failures += check("parse_due today date", due.date != null && due.date.length == 10);
        failures += check("parse_due today clears time", due.time == null);
        var due2 = parse_due(parser, "@10am");
        failures += check("parse_due @ keeps time", due2.time == "10:00");
        var due3 = parse_due(parser, "2026-08-07");
        failures += check("parse_due absolute", due3.date == "2026-08-07" && due3.time == null);
    } catch (GLib.Error e) {
        print("FAIL: parse_due threw: %s\n", e.message);
        failures += 4;
    }

    // CLI JSON escaping (System.Text.Json parity)
    failures += check("escape ascii", CliJson.escape_string("ASCII") == "\"ASCII\"");
    failures += check("escape quote", CliJson.escape_string("a\"b") == "\"a\\\"b\"");
    failures += check("escape newline", CliJson.escape_string("l\nb") == "\"l\\nb\"");
    failures += check("escape utf8", CliJson.escape_string("买") == "\"\\u4e70\"");

    // i18n flat-JSON parser
    var table = new GLib.HashTable<string, string>(str_hash, str_equal);
    I18n.parse_flat_json("{ \"a\": \"x\\ny\", \"b\": \"引\\\"号\" }", table);
    failures += check("i18n parse value", table.lookup("a") == "x\ny");
    failures += check("i18n parse utf8+quote", table.lookup("b") == "引\"号");
    var i18n = new I18n("en");
    failures += check("i18n en", i18n.t("navToday") == "Today");
    i18n.set_language("zh");
    failures += check("i18n zh", i18n.t("navToday") == "今天");
    failures += check("i18n fallback key", i18n.t("__missing__") == "__missing__");

    // Database contract (fresh DB in tmp)
    try {
        var dir = DirUtils.make_tmp("taskly-test-XXXXXX");
        var db = new SQLiteDatabase();
        db.set_database_path(GLib.Path.build_filename(dir, "test.db"));
        db.ensure_connected();

        var lists = db.get_all_lists();
        failures += check("default list seeded", lists.length() == 1);
        failures += check("default list name", lists.nth_data(0).name == "工作");
        failures += check("default list icon", lists.nth_data(0).icon == DEFAULT_LIST_ICON);
        failures += check("default list color", lists.nth_data(0).color == DEFAULT_LIST_COLOR);
        failures += check("schema version", db.schema_version() == SQLiteDatabase.DATABASE_VERSION);

        var list_id = db.add_list("Test", "🎯", (int32) 0xFF007AFFu);
        var task = new TaskItem();
        task.list_id = list_id;
        task.text = "买牛奶";
        task.created_at = DateParser.created_at_now();
        task.due_date = "2026-08-07";
        task.due_time = "10:30";
        task.notes = "note1";
        task.id = db.add_task(task);

        var loaded = db.get_task_by_id(task.id);
        failures += check("task roundtrip", loaded != null && loaded.text == "买牛奶"
            && loaded.due_date == "2026-08-07" && loaded.due_time == "10:30");

        failures += check("set completed", db.set_task_completed(task.id, true) > 0);
        failures += check("completed flag", db.get_task_by_id(task.id).completed);
        failures += check("toggle flips", db.toggle_task_completed(task.id) > 0
            && !db.get_task_by_id(task.id).completed);

        failures += check("search hit", db.search_tasks("牛奶").length() == 1);
        failures += check("search miss", db.search_tasks("不存在").length() == 0);

        // Calendar data-layer contract (PRODUCT-SPEC 4b): bounds inclusive,
        // due_date ASC ordering, incomplete-only unless requested, and day
        // dots count incomplete tasks per date.
        var seed_range = new TaskItem();
        seed_range.list_id = list_id;
        seed_range.created_at = "x";
        seed_range.text = "early";
        seed_range.due_date = "2026-09-01";
        db.add_task(seed_range);
        var seed_mid = new TaskItem();
        seed_mid.list_id = list_id;
        seed_mid.created_at = "x";
        seed_mid.text = "mid";
        seed_mid.due_date = "2026-09-15";
        db.add_task(seed_mid);
        var seed_late = new TaskItem();
        seed_late.list_id = list_id;
        seed_late.created_at = "x";
        seed_late.text = "late";
        seed_late.due_date = "2026-09-30";
        db.add_task(seed_late);
        var seed_out = new TaskItem();
        seed_out.list_id = list_id;
        seed_out.created_at = "x";
        seed_out.text = "outside";
        seed_out.due_date = "2026-10-05";
        db.add_task(seed_out);

        var in_range = db.get_tasks_in_range("2026-09-01", "2026-09-30");
        failures += check("range count", in_range.length() == 3);
        failures += check("range order", in_range.nth_data(0).due_date == "2026-09-01"
            && in_range.nth_data(1).due_date == "2026-09-15"
            && in_range.nth_data(2).due_date == "2026-09-30");

        db.set_task_completed(seed_mid.id, true);
        failures += check("range excludes completed",
            db.get_tasks_in_range("2026-09-01", "2026-09-30").length() == 2);
        failures += check("range includes completed",
            db.get_tasks_in_range("2026-09-01", "2026-09-30", true).length() == 3);

        var day_counts = db.get_due_day_counts("2026-09-01", "2026-09-30");
        bool found_mid_done = false;
        bool found_first = false;
        foreach (var item in day_counts) {
            if (item.date == "2026-09-15" && item.count == 0) {
                found_mid_done = true;
            }
            if (item.date == "2026-09-01" && item.count == 1) {
                found_first = true;
            }
        }
        failures += check("day dots incomplete only", !found_mid_done && found_first);

        var list2 = db.add_list("Doomed", null, null);
        var t2 = new TaskItem();
        t2.list_id = list2;
        t2.text = "x";
        t2.created_at = "x";
        db.add_task(t2);
        db.delete_list(list2);
        failures += check("cascade delete", db.get_tasks_by_list(list2).length() == 0);
    } catch (GLib.Error e) {
        print("DB test error: %s\n", e.message);
        failures++;
    }

    if (failures == 0) {
        print("all contract tests passed\n");
        return 0;
    }
    print("%d contract test(s) FAILED\n", failures);
    return 1;
}

private int check(string name, bool ok) {
    if (!ok) {
        print("FAIL: %s\n", name);
        return 1;
    }
    return 0;
}

}
