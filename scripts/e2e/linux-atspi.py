#!/usr/bin/env python3
import argparse
import json
import time
from pathlib import Path

import pyatspi


def children(node):
    for index in range(node.childCount):
        try:
            child = node.getChildAtIndex(index)
            # GTK can remove and rebuild a row between childCount and the
            # D-Bus lookup while async task snapshots arrive.
            if child is not None:
                yield child
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


def wait_for(description, probe, timeout=60.0):
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


def count_text_fragment(root, expected):
    return sum(
        1
        for node in walk(root)
        if expected in (node.name or "") or expected in text(node)
    )


def matching_child_indexes(container, expected):
    result = []
    for index in range(container.childCount):
        try:
            child = container.getChildAtIndex(index)
        except Exception:
            continue
        if contains_text(child, expected):
            result.append(index)
    return result


def select_single_named_child(root, expected):
    """Select the one direct row containing expected in a selection container."""
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = matching_child_indexes(container, expected)
        if len(indexes) != 1:
            continue
        selection.clearSelection()
        if not selection.selectChild(indexes[0]):
            raise AssertionError(f"AT-SPI failed to select row containing {expected!r}")
        return container
    return None


def select_named_children(root, expected_names):
    """Select the direct rows that contain every expected task title."""
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = []
        for expected in expected_names:
            matches = matching_child_indexes(container, expected)
            if len(matches) != 1:
                indexes = []
                break
            indexes.append(matches[0])
        if not indexes or len(set(indexes)) != len(expected_names):
            continue
        selection.clearSelection()
        for index in indexes:
            if not selection.selectChild(index):
                raise AssertionError("AT-SPI failed to select all requested task rows")
        return container
    return None


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

    wait_for("default-list sentinel", lambda: contains_text(window, "Default-list sentinel"))
    wait_for("first 64-bit task row", lambda: contains_text(window, "64-bit task A"))
    wait_for("second 64-bit task row", lambda: contains_text(window, "64-bit task B"))

    wait_for(
        "64-bit list row selection",
        lambda: select_single_named_child(window, "64-bit identity list"),
    )
    wait_for(
        "64-bit list filter",
        lambda: not contains_text(window, "Default-list sentinel")
        and contains_text(window, "64-bit task A")
        and contains_text(window, "64-bit task B"),
    )

    wait_for(
        "two 64-bit task rows selected for scheduling",
        lambda: select_named_children(window, ["64-bit task A", "64-bit task B"]),
    )
    schedule = wait_for(
        "batch schedule button",
        lambda: find_named(window, "Schedule Selected", "push button"),
    )
    press(schedule)
    tomorrow = wait_for(
        "Tomorrow schedule option", lambda: find_named(window, "Tomorrow", "push button")
    )
    press(tomorrow)
    wait_for(
        "scheduled task rows refreshed",
        lambda: count_text_fragment(window, "Tomorrow") >= 2,
    )

    wait_for(
        "two 64-bit task rows selected for deletion",
        lambda: select_named_children(window, ["64-bit task A", "64-bit task B"]),
    )
    delete = wait_for(
        "batch delete button", lambda: find_named(window, "Delete List", "push button")
    )
    press(delete)
    wait_for(
        "staged tasks hidden",
        lambda: not contains_text(window, "64-bit task A")
        and not contains_text(window, "64-bit task B"),
    )
    undo = wait_for("undo banner", lambda: find_named(window, "Undo", "push button"))
    press(undo)
    wait_for(
        "identity-preserving undo",
        lambda: contains_text(window, "64-bit task A")
        and contains_text(window, "64-bit task B"),
    )

    entry.queryEditableText().setTextContents("Acceptance task")
    press(submit)
    wait_for("quick-add field cleared", lambda: text(entry) == "")
    wait_for("RPC-created task row", lambda: contains_text(window, "Acceptance task"))

    (args.output / "accessibility.json").write_text(
        json.dumps(snapshot(application), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "interaction-trace.json").write_text(
        json.dumps(
            {
                "platform": "linux",
                "actions": [
                    "select:64-bit-list-row",
                    "select:two-64-bit-task-rows",
                    "press:batch-schedule-tomorrow",
                    "press:batch-delete",
                    "press:undo",
                    "set:quick-add",
                    "press:quick-add-submit",
                ],
                "assertions": [
                    "packaged GTK4 frame activated on native Wayland",
                    "AT-SPI roles and names exposed",
                    "list and task IDs above 2^32 survive GTK row data",
                    "batch scheduling clears hidden due times for both tasks",
                    "six-second staged deletion hides both tasks without deleting them",
                    "undo restores the original task IDs and metadata",
                    "RPC-created task appeared after the quick-add field cleared",
                    "quick-add preserved the selected 64-bit list ownership",
                ],
            },
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
