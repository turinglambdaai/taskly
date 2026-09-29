# Golden CLI suite

Shared fixture proving that identical argv produces identical
stdout/stderr/exit code on every platform binary (contract:
`shared/spec/CLI-SPEC.md`).

## Layout

| File | Role |
|---|---|
| `cases.json` | Inputs: `name`, `args`, optional `pre` (unasserted setup commands), optional `seed` (`seed.sql` default) |
| `seed.sql` / `seed-empty.sql` | Schema v4 + fixed data; every case gets a fresh copy |
| `golden/<case>.{out,err,exit}` | Expected bytes (normalized) |
| `runner.py` | Cross-platform runner, stdlib-only |

## Running

```bash
# macOS (after `swift build` in apps/macos)
cd apps/macos && scripts/golden-cli.sh            # verify
scripts/golden-cli.sh --record                    # re-record after an intentional spec change

# any platform, directly
python3 shared/cli-golden/runner.py --binary /path/to/Taskly [--record]
```

Dynamic values are normalized before comparison (see CLI-SPEC § Golden
CLI suite): timestamps → `{{now}}`, today/tomorrow → `{{today}}` /
`{{tomorrow}}`, and the OS-specific suffix after `Cannot open database:
<path>` is dropped.

## Rules

- Verify mode fails on missing golden files — new cases must be recorded
  and reviewed, never silently skipped in CI.
- Never add a case with empty `args` (that opens the GUI).
- `install-cli` / `uninstall-cli` are out of scope (they mutate
  PATH/shell files).
- After an intentional behavior change: change `shared/spec/CLI-SPEC.md`
  first, then `--record`, review the diff against the spec, and commit
  both together.
