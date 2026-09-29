#!/usr/bin/env python3
"""Taskly golden-CLI suite runner (cross-platform, stdlib only).

Drives a built Taskly binary through shared/cli-golden/cases.json and
compares stdout/stderr/exit code byte-for-byte against golden/<name>.*
files. Identical argv must produce identical JSON/exit codes on every
platform (shared/spec/CLI-SPEC.md).

Each case runs against a fresh database seeded from seed.sql (or the
case's "seed" override), so cases are independent and order-free. "pre"
commands run before the asserted command to build dynamic state (e.g.
tasks due today); their output is discarded but a non-zero exit fails
the case.

Dynamic values are normalized in actual output before comparison:
  ISO-8601 local timestamps  -> {{now}}
  tomorrow's date (yyyy-MM-dd) -> {{tomorrow}}
  today's date (yyyy-MM-dd)    -> {{today}}

Usage:
  python3 runner.py --binary /path/to/Taskly [--record]
Without --record the suite verifies; missing golden files are failures,
so CI never silently passes a newly added case.
"""

import argparse
import datetime
import json
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parent

ISO_TS = re.compile(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})")


def normalize(text: str, dynamic_dates: bool) -> str:
    tomorrow = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    today = datetime.date.today().isoformat()
    text = ISO_TS.sub("{{now}}", text)
    # {{today}}/{{tomorrow}} only for cases that use relative --due
    # expressions — a static yyyy-MM-dd fixture date must never be
    # rewritten just because the calendar caught up with it.
    if dynamic_dates:
        text = text.replace(tomorrow, "{{tomorrow}}")
        text = text.replace(today, "{{today}}")
    # Detail after the path in "Cannot open database:" is OS-specific
    # (Cocoa / Win32 / errno strings); CLI-SPEC pins only the prefix.
    # Not line-anchored: the message sits inside a JSON string on stderr.
    text = re.sub(r"(Cannot open database: [^(\"]*?)\s*\([^)]*\)", r"\1", text)
    return text


def seed_database(db_path: Path, seed_sql: str) -> None:
    conn = sqlite3.connect(str(db_path))
    try:
        conn.executescript(seed_sql)
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        if version != 4:
            raise RuntimeError(f"seed produced user_version={version}, expected 4")
    finally:
        conn.close()


def run_case(binary: str, case: dict, work_dir: Path, seed_sqls: dict) -> dict:
    db_path = work_dir / f"{case['name']}.db"
    seed_database(db_path, seed_sqls[case.get("seed", "seed.sql")])
    full_args = [binary, "--db", str(db_path)]

    def invoke(argv):
        return subprocess.run(full_args + argv, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=60)

    for pre_argv in case.get("pre", []):
        pre = invoke(pre_argv)
        if pre.returncode != 0:
            raise RuntimeError(
                f"pre command {pre_argv} failed ({pre.returncode}): {pre.stderr.strip()}")

    result = invoke(case["args"])
    dyn = bool(case.get("dynamicDates"))
    return {
        "out": normalize(result.stdout, dyn),
        "err": normalize(result.stderr, dyn),
        "exit": str(result.returncode),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Taskly golden-CLI suite")
    parser.add_argument("--binary", required=True, help="Path to the Taskly binary")
    parser.add_argument("--record", action="store_true",
                        help="Write actual outputs as golden files instead of verifying")
    parser.add_argument("--cases", default=str(SHARED_DIR / "cases.json"))
    parser.add_argument("--golden-dir", default=str(SHARED_DIR / "golden"))
    args = parser.parse_args()

    import tempfile
    cases = json.loads(Path(args.cases).read_text(encoding="utf-8"))["cases"]
    names = [c["name"] for c in cases]
    if len(names) != len(set(names)):
        dupes = sorted(n for n in names if names.count(n) > 1)
        print(f"FAIL duplicate case names: {dupes}", file=sys.stderr)
        return 2
    for case in cases:
        if not case.get("args"):
            # Empty argv opens the GUI — never allowed in the suite.
            print(f"FAIL case '{case['name']}' has empty args", file=sys.stderr)
            return 2

    seed_sqls = {name: (SHARED_DIR / name).read_text(encoding="utf-8")
                 for name in {c.get("seed", "seed.sql") for c in cases}}

    golden_dir = Path(args.golden_dir)
    passed, failed = 0, 0
    with tempfile.TemporaryDirectory(prefix="taskly-golden-") as tmp:
        work_dir = Path(tmp)
        for case in cases:
            name = case["name"]
            try:
                actual = run_case(args.binary, case, work_dir, seed_sqls)
            except Exception as exc:  # noqa: BLE001 — report and continue
                print(f"FAIL {name}: {exc}", file=sys.stderr)
                failed += 1
                continue

            expected_files = {ext: golden_dir / f"{name}.{ext}" for ext in ("out", "err", "exit")}
            if args.record:
                golden_dir.mkdir(parents=True, exist_ok=True)
                for ext in ("out", "err", "exit"):
                    expected_files[ext].write_text(actual[ext], encoding="utf-8")
                print(f"RECORDED {name}")
                passed += 1
                continue

            if not all(f.exists() for f in expected_files.values()):
                print(f"FAIL {name}: missing golden files — run with --record to create",
                      file=sys.stderr)
                failed += 1
                continue

            diffs = []
            for ext in ("out", "err", "exit"):
                expected = expected_files[ext].read_text(encoding="utf-8")
                if expected != actual[ext]:
                    import difflib
                    diff = difflib.unified_diff(
                        expected.splitlines(keepends=True), actual[ext].splitlines(keepends=True),
                        fromfile=f"golden/{name}.{ext}", tofile=f"actual/{name}.{ext}")
                    diffs.append("".join(diff))
            if diffs:
                print(f"FAIL {name} (args: {case['args']})", file=sys.stderr)
                for diff in diffs:
                    print(diff, file=sys.stderr)
                failed += 1
            else:
                passed += 1

    mode = "recorded" if args.record else "passed"
    print(f"\n{passed}/{passed + failed} cases {mode}, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
