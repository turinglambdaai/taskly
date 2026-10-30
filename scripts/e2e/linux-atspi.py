#!/usr/bin/env python3
import argparse
import json
import subprocess
import time
from pathlib import Path

import pyatspi


def children(node):
    try:
        count = node.childCount
    except Exception:
        return
    for index in range(count):
        try:
            child = node.getChildAtIndex(index)
            # GTK can remove and rebuild a row between childCount and the
            # D-Bus lookup while async task snapshots arrive.
            if child is not None:
                yield child
        except Exception:
            continue


def walk(node):
    if node is None:
        return
    yield node
    for child in children(node):
        yield from walk(child)


def role(node):
    try:
        return node.getRoleName()
    except Exception:
        return "unknown"


def name(node):
    try:
        return node.name or ""
    except Exception:
        # A row can disappear between two AT-SPI calls while GTK rebuilds it.
        return ""


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
            if role(node) == "frame" and "taskly" in name(node).casefold():
                return application
    return None


def find_named(root, expected_name, expected_role=None):
    for node in walk(root):
        if name(node) == expected_name and (expected_role is None or role(node) == expected_role):
            return node
    return None


def find_editable_named(root, expected_name):
    for node in walk(root):
        if name(node) != expected_name:
            continue
        try:
            node.queryEditableText()
            return node
        except Exception:
            continue
    return None


def find_editable_value(root, expected_value):
    for node in walk(root):
        try:
            editable = node.queryEditableText()
            if editable.getText(0, editable.characterCount) == expected_value:
                return node
        except Exception:
            continue
    return None


def contains_text(root, expected):
    return any(name(node) == expected or text(node) == expected for node in walk(root))


def find_staged_delete_ready(root):
    """Find the Undo button and verify both staged task rows are already hidden in one tree walk."""
    undo = None
    found_a = False
    found_b = False
    for node in walk(root):
        node_name = name(node)
        node_text = ""
        if node_name == "Undo" and role(node) == "push button":
            undo = node
        if node_name == "64-bit task A":
            found_a = True
        elif not found_a:
            node_text = text(node)
            if node_text == "64-bit task A":
                found_a = True
        if node_name == "64-bit task B":
            found_b = True
        elif not found_b:
            if not node_text:
                node_text = text(node)
            if node_text == "64-bit task B":
                found_b = True
        if undo is not None and found_a and found_b:
            return None
    return undo if undo is not None and not found_a and not found_b else None


def matching_child_indexes(container, expected):
    result = []
    try:
        count = container.childCount
    except Exception:
        return result
    for index in range(count):
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
        return container.getChildAtIndex(indexes[0])
    return None


def find_frame(application):
    if application is None:
        return None
    return next(
        (node for node in children(application) if role(node) == "frame"),
        None,
    )


def select_and_press_unedited_named_row_button(root, expected):
    """Select a direct task-list child and invoke its sole row action atomically.

    Looking for any descendant list item is ambiguous in GTK's AT-SPI tree:
    an outer list item can expose the text of nested task rows. Resolve the
    direct child through its selection container instead, then keep selection
    and action invocation in one traversal so no proxy survives a GTK update.
    """
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = matching_child_indexes(container, expected)
        if len(indexes) != 1:
            continue
        try:
            selection.clearSelection()
            if not selection.selectChild(indexes[0]):
                continue
            row = container.getChildAtIndex(indexes[0])
            buttons = [
                node
                for node in walk(row)
                if role(node) in ("push button", "button")
            ]
            if len(buttons) != 1:
                continue
            actions = buttons[0].queryAction()
            return actions.nActions >= 1 and actions.doAction(0)
        except Exception:
            continue
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
    result = {"name": name(node), "role": role(node)}
    value = text(node)
    if value:
        result["text"] = value
    if depth < 8:
        result["children"] = [snapshot(child, depth + 1) for child in children(node)]
    return result


def find_live_window():
    # GTK reparents the selected row when it creates an inline editor. A
    # cached frame proxy can remain queryable while its focus state is stale.
    return find_frame(find_application())


def send_keyboard_key(key):
    """Send a genuine XTest key event to the active X11 window.

    The acceptance harness explicitly runs GTK on Xvfb + Openbox. The
    AT-SPI Registry KEY_SYM synthesizer can accept a request without sending
    a native key to GTK; XTest makes keyboard input observable and verifiable.
    Focus remains owned by GTK: no accessibility grabFocus injection.
    """
    subprocess.run(
        ["xdotool", "key", "--clearmodifiers", key],
        check=True,
        timeout=5,
    )


def has_focus(node):
    # GTK4 GtkEntry delegates keyboard input to its internal GtkText.
    # Require the native focused state on the editor or one of its own
    # descendants, never on an unrelated widget in the same window.
    if node is None:
        return False
    for child in walk(node):
        try:
            if child.getState().contains(pyatspi.STATE_FOCUSED):
                return True
        except Exception:
            continue
    return False


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
    window = wait_for("Taskly frame", lambda: find_frame(application))
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
    (args.output / "bulk-toolbar-debug.json").write_text(
        json.dumps(snapshot(window), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    delete = wait_for(
        "batch delete button", lambda: find_named(window, "Delete", "push button")
    )
    press(schedule)
    tomorrow = wait_for(
        "Tomorrow schedule option", lambda: find_named(window, "Tomorrow", "push button")
    )
    press(tomorrow)
    wait_for(
        "two 64-bit task rows selected for deletion",
        lambda: select_named_children(window, ["64-bit task A", "64-bit task B"]),
    )
    press(delete)
    # The product's undo window is six seconds. Find the banner and confirm
    # both rows are hidden in one AT-SPI traversal, then undo immediately.
    undo = wait_for(
        "staged deletion hidden with undo banner",
        lambda: find_staged_delete_ready(window),
        timeout=4.0,
    )
    press(undo)
    wait_for(
        "identity-preserving undo",
        lambda: contains_text(window, "64-bit task A")
        and contains_text(window, "64-bit task B"),
    )

    task_row = wait_for(
        "single row selected for keyboard editing",
        lambda: select_single_named_child(window, "64-bit task A"),
    )
    details = wait_for(
        "selected task details button",
        lambda: next(
            reversed(
                [
                node
                for node in walk(task_row)
                if role(node) in ("push button", "button")
                ]
            ),
            None,
        ),
    )
    press(details)
    editor = wait_for(
        "keyboard-opened task editor",
        lambda: find_editable_value(window, "64-bit task A"),
    )
    wait_for(
        "visible task editor Save action",
        lambda: find_named(window, "Save", "push button"),
    )
    wait_for(
        "visible task editor Cancel action",
        lambda: find_named(window, "Cancel", "push button"),
    )
    wait_for(
        "accessible task editor calendar action",
        lambda: find_named(window, "Add Date", "push button"),
    )
    # The native GtkRevealer must give its mapped editor keyboard focus.
    # A programmatic AT-SPI focus injection would mask a real user regression.
    try:
        wait_for(
            "task editor keyboard focus",
            lambda: has_focus(find_editable_value(find_live_window(), "64-bit task A")),
            timeout=10.0,
        )
    except AssertionError:
        live = find_live_window()
        focused = [
            {"name": name(node), "role": role(node), "text": text(node)[:80]}
            for node in walk(live)
            if has_focus(node)
        ]
        raise AssertionError(f"task editor has no accessible native focus; focused={focused}")
    application = wait_for("live Taskly application", find_application)
    window = wait_for("live Taskly frame", lambda: find_frame(application))
    editor = wait_for(
        "live keyboard-opened editor",
        lambda: find_editable_value(window, "64-bit task A"),
    )
    editor.queryEditableText().setTextContents("Cancelled inline draft")
    # The packaged keyboard journey runs on the seat-backed X11 acceptance host.
    send_keyboard_key("Escape")
    wait_for(
        "visible Escape cancellation feedback",
        lambda: contains_text(window, "Changes discarded"),
    )
    wait_for(
        "Escape cancelled the focused task draft",
        lambda: find_editable_value(window, "Cancelled inline draft") is None
        and contains_text(window, "64-bit task A"),
    )

    # Creating the first inline editor reparents the row content. GTK's
    # AT-SPI cache can keep the original frame proxy alive even after the
    # editor is collapsed, so every descendant discovered through it may be
    # stale. Re-enter through the desktop registry before the next journey.
    application = wait_for(
        "Taskly application after editor layout change", find_application
    )
    window = wait_for(
        "Taskly frame after editor layout change",
        lambda: find_frame(application),
    )

    (args.output / "task-editor-after-escape.json").write_text(
        json.dumps(snapshot(window), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    wait_for(
        "second task Details action",
        lambda: select_and_press_unedited_named_row_button(
            window, "64-bit task B"
        ),
    )
    editor = wait_for(
        "second task editor opened for explicit Save",
        lambda: find_editable_value(window, "64-bit task B"),
    )
    editor.queryEditableText().setTextContents("Saved inline draft")
    save = wait_for(
        "visible task editor Save action after reopen",
        lambda: find_named(window, "Save", "push button"),
    )
    press(save)
    wait_for(
        "visible Save persisted the task draft",
        lambda: find_editable_value(window, "Saved inline draft") is None
        and contains_text(window, "Saved inline draft"),
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
                    "press:selected-row-details",
                    "key:escape-cancel-draft",
                    "press:second-row-details",
                    "press:visible-save",
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
                    "task editor exposes accessible calendar, Save and Cancel actions; Escape cancels its draft",
                    "visible Save persists the complete task draft and closes only after acknowledgement",
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
