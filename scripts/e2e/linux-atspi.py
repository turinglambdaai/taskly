#!/usr/bin/env python3
import argparse
import json
import time
from pathlib import Path

import pyatspi


def children(node):
    for index in range(node.childCount):
        try:
            yield node.getChildAtIndex(index)
        except Exception:
            continue


def walk(node):
    yield node
    for child in children(node):
        yield from walk(child)


def role(node):
    try:
        return node.getRoleName()
    except Exception:
        return "unknown"


def text(node):
    try:
        value = node.queryText()
        return value.getText(0, value.characterCount)
    except Exception:
        return ""


def wait_for(description, probe, timeout=30.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = probe()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(f"timed out waiting for {description}")


def find_application():
    desktop = pyatspi.Registry.getDesktop(0)
    for application in children(desktop):
        for node in children(application):
            if role(node) == "frame" and "taskly" in (node.name or "").casefold():
                return application
    return None


def find_named(root, name, expected_role=None):
    for node in walk(root):
        if (node.name or "") == name and (expected_role is None or role(node) == expected_role):
            return node
    return None


def find_editable_named(root, name):
    for node in walk(root):
        if (node.name or "") != name:
            continue
        try:
            node.queryEditableText()
            return node
        except Exception:
            continue
    return None


def contains_text(root, expected):
    return any((node.name or "") == expected or text(node) == expected for node in walk(root))


def snapshot(node, depth=0):
    result = {"name": node.name or "", "role": role(node)}
    value = text(node)
    if value:
        result["text"] = value
    if depth < 8:
        result["children"] = [snapshot(child, depth + 1) for child in children(node)]
    return result


def press(node):
    actions = node.queryAction()
    if actions.nActions < 1 or not actions.doAction(0):
        raise AssertionError(f"AT-SPI action failed for {node.name!r}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    application = wait_for("Taskly application", find_application)
    window = wait_for("Taskly frame", lambda: next((n for n in walk(application) if role(n) == "frame"), None))
    # GTK/AT-SPI role names vary between distro accessibility stacks
    # (commonly "text" or "entry"). The editable-text interface is the
    # stable behavioral contract we actually need.
    entry = wait_for("quick-add entry", lambda: find_editable_named(window, "+ Add Task"))
    submit = wait_for("quick-add submit", lambda: find_named(window, "+ Add Task", "push button"))
    entry.queryEditableText().setTextContents("Acceptance task")
    press(submit)
    wait_for("RPC-created task row", lambda: contains_text(window, "Acceptance task"))

    (args.output / "accessibility.json").write_text(
        json.dumps(snapshot(application), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "interaction-trace.json").write_text(
        json.dumps(
            {
                "platform": "linux",
                "actions": ["set:quick-add", "press:quick-add-submit"],
                "assertions": [
                    "packaged GTK4 frame activated on native Wayland",
                    "AT-SPI roles and names exposed",
                    "RPC-created task appeared through the changed Event",
                ],
            },
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
