import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { switch self { case .failure(let message): return message } }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ element: AXUIElement) -> [AXUIElement] {
    [element] + children(element).flatMap(walk)
}

func find(_ root: AXUIElement, identifier: String) -> AXUIElement? {
    walk(root).first { stringAttribute($0, kAXIdentifierAttribute) == identifier }
}

func find(_ root: AXUIElement, identifierPrefix: String) -> AXUIElement? {
    walk(root).first {
        stringAttribute($0, kAXIdentifierAttribute).hasPrefix(identifierPrefix)
    }
}

func findTaskTitle(_ root: AXUIElement, text: String) -> AXUIElement? {
    walk(root).first { element in
        stringAttribute(element, kAXIdentifierAttribute).hasPrefix("task-title-") &&
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(element, $0) == text }
    }
}

func findDeleteMenuItem(_ root: AXUIElement) -> AXUIElement? {
    walk(root).first { element in
        stringAttribute(element, kAXRoleAttribute) == (kAXMenuItemRole as String) &&
            ["Delete", "删除"].contains(stringAttribute(element, kAXTitleAttribute))
    }
}

func containsStaticText(_ root: AXUIElement, _ expected: String) -> Bool {
    walk(root).contains { element in
        stringAttribute(element, kAXRoleAttribute) == (kAXStaticTextRole as String) &&
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(element, $0) == expected }
    }
}

func waitFor<T>(_ description: String, timeout: TimeInterval = 30, probe: () -> T?) throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let value = probe() { return value }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw DriverError.failure("timed out waiting for \(description)")
}

func snapshot(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    var result: [String: Any] = [
        "role": stringAttribute(element, kAXRoleAttribute),
        "identifier": stringAttribute(element, kAXIdentifierAttribute),
        "title": stringAttribute(element, kAXTitleAttribute),
        "label": stringAttribute(element, kAXDescriptionAttribute),
        "value": stringAttribute(element, kAXValueAttribute),
    ]
    if depth < 8 { result["children"] = children(element).map { snapshot($0, depth: depth + 1) } }
    return result
}

func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func press(_ element: AXUIElement, _ description: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else {
        throw DriverError.failure("AXPress failed for \(description): \(result.rawValue)")
    }
}

func typeText(_ value: String, into element: AXUIElement) throws {
    guard AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute as CFString, kCFBooleanTrue
    ) == .success else {
        throw DriverError.failure("could not focus quick-add field")
    }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
        throw DriverError.failure("could not create native keyboard events")
    }
    let characters = Array(value.utf16)
    characters.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

func setValue(_ value: String, on element: AXUIElement) throws {
    guard AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute as CFString, kCFBooleanTrue
    ) == .success else {
        throw DriverError.failure("could not focus editor")
    }
    guard AXUIElementSetAttributeValue(
        element, kAXValueAttribute as CFString, value as CFString
    ) == .success else {
        throw DriverError.failure("could not set editor value")
    }
}

func postKey(_ keyCode: CGKeyCode) throws {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw DriverError.failure("could not create keyboard event")
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

func rightClick(_ element: AXUIElement) throws {
    guard let positionRaw = attribute(element, kAXPositionAttribute),
          let sizeRaw = attribute(element, kAXSizeAttribute),
          CFGetTypeID(positionRaw) == AXValueGetTypeID(),
          CFGetTypeID(sizeRaw) == AXValueGetTypeID() else {
        throw DriverError.failure("element has no clickable bounds")
    }
    let positionValue = positionRaw as! AXValue
    let sizeValue = sizeRaw as! AXValue
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size),
          let source = CGEventSource(stateID: .hidSystemState) else {
        throw DriverError.failure("could not resolve clickable bounds")
    }
    let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    guard let down = CGEvent(
        mouseEventSource: source, mouseType: .rightMouseDown,
        mouseCursorPosition: point, mouseButton: .right),
          let up = CGEvent(
            mouseEventSource: source, mouseType: .rightMouseUp,
            mouseCursorPosition: point, mouseButton: .right) else {
        throw DriverError.failure("could not create right-click events")
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

var diagnosticApplication: AXUIElement?
var diagnosticOutput: URL?

do {
    let arguments = CommandLine.arguments
    guard let pidIndex = arguments.firstIndex(of: "--pid"), pidIndex + 1 < arguments.count,
          let pid = Int32(arguments[pidIndex + 1]),
          let outputIndex = arguments.firstIndex(of: "--output"), outputIndex + 1 < arguments.count else {
        throw DriverError.failure("usage: macos-ax --pid PID --output DIRECTORY")
    }
    let output = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
    diagnosticOutput = output
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    guard AXIsProcessTrusted() else { throw DriverError.failure("accessibility access is unavailable") }

    let application = AXUIElementCreateApplication(pid)
    diagnosticApplication = application
    let window: AXUIElement = try waitFor("Taskly window") {
        (attribute(application, kAXWindowsAttribute) as? [AXUIElement])?.first
    }
    _ = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)

    for view in ["today", "planned", "all", "completed"] {
        let _: AXUIElement = try waitFor("visible zero count for \(view)") {
            guard let candidate = find(window, identifier: "smart-view-\(view)") else { return nil }
            return [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(candidate, $0) == "0" } ? candidate : nil
        }
    }

    let quickAdd: AXUIElement = try waitFor("quick-add field") { find(window, identifier: "quick-add") }
    let submit: AXUIElement = try waitFor("quick-add submit button") { find(window, identifier: "quick-add-submit") }
    try typeText("Acceptance task", into: quickAdd)
    _ = try waitFor("native quick-add input") {
        stringAttribute(quickAdd, kAXValueAttribute) == "Acceptance task" ? true : nil
    }
    try press(submit, "quick-add-submit")
    _ = try waitFor("quick-add submission") {
        stringAttribute(quickAdd, kAXValueAttribute).isEmpty ? true : nil
    }
    _ = try waitFor("RPC-created task row") { containsStaticText(window, "Acceptance task") ? true : nil }

    let taskTitle: AXUIElement = try waitFor("identified task title") {
        findTaskTitle(window, text: "Acceptance task")
    }
    let taskIdentifier = stringAttribute(taskTitle, kAXIdentifierAttribute)
    guard let taskID = taskIdentifier.split(separator: "-").last.map(String.init) else {
        throw DriverError.failure("task title had no stable id: \(taskIdentifier)")
    }

    // Escape is a true draft cancel even while the native field editor owns
    // focus. Return commits, and the same stable task ID remains visible.
    let details: AXUIElement = try waitFor("task details control") {
        find(window, identifier: "task-details-\(taskID)")
    }
    try press(details, "task-details-\(taskID)")
    let cancelledEditor: AXUIElement = try waitFor("inline title editor") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    try setValue("Cancelled draft", on: cancelledEditor)
    try postKey(53) // Escape
    _ = try waitFor("Escape cancelled inline draft") {
        find(window, identifier: "inline-task-title-\(taskID)") == nil &&
            findTaskTitle(window, text: "Acceptance task") != nil ? true : nil
    }

    let detailsAgain: AXUIElement = try waitFor("task details control after cancel") {
        find(window, identifier: "task-details-\(taskID)")
    }
    try press(detailsAgain, "task-details-\(taskID)")
    let committedEditor: AXUIElement = try waitFor("inline title editor after cancel") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    let explicitSave: AXUIElement = try waitFor("visible inline Save action") {
        find(window, identifier: "inline-task-save-\(taskID)")
    }
    let _: AXUIElement = try waitFor("visible inline Cancel action") {
        find(window, identifier: "inline-task-cancel-\(taskID)")
    }
    try setValue("Edited acceptance task", on: committedEditor)
    try press(explicitSave, "inline-task-save-\(taskID)")
    _ = try waitFor("visible Save committed inline draft") {
        findTaskTitle(window, text: "Edited acceptance task") != nil &&
            find(window, identifier: "inline-task-title-\(taskID)") == nil ? true : nil
    }

    let detailsForReturn: AXUIElement = try waitFor("task details control after Save") {
        find(window, identifier: "task-details-\(taskID)")
    }
    try press(detailsForReturn, "task-details-\(taskID)")
    let returnEditor: AXUIElement = try waitFor("inline title editor for Return") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    try setValue("Return-edited acceptance task", on: returnEditor)
    try postKey(36) // Return
    _ = try waitFor("Return committed inline draft") {
        findTaskTitle(window, text: "Return-edited acceptance task") != nil ? true : nil
    }

    // Native context-menu deletion is staged for six seconds. Undo restores
    // the exact original row ID because no backend delete has happened yet.
    let editedTitle: AXUIElement = try waitFor("identified edited task title") {
        findTaskTitle(window, text: "Return-edited acceptance task")
    }
    try rightClick(editedTitle)
    let deleteItem: AXUIElement = try waitFor("task Delete menu item") {
        findDeleteMenuItem(application)
    }
    try press(deleteItem, "Delete")
    let undo: AXUIElement = try waitFor("undo-delete action") {
        find(window, identifier: "undo-delete")
    }
    _ = try waitFor("staged deletion hidden") {
        find(window, identifier: "task-title-\(taskID)") == nil ? true : nil
    }
    try press(undo, "undo-delete")
    _ = try waitFor("identity-preserving undo") {
        find(window, identifier: "task-title-\(taskID)") != nil ? true : nil
    }

    let completion: AXUIElement = try waitFor("task completion control") {
        find(window, identifier: "task-complete-\(taskID)")
    }
    let completionIdentifier = stringAttribute(completion, kAXIdentifierAttribute)
    try press(completion, completionIdentifier)
    _ = try waitFor("changed Event reflected in the active view") {
        containsStaticText(window, "Acceptance task") ? nil : true
    }

    try writeJSON(snapshot(application), to: output.appendingPathComponent("accessibility.json"))
    let screenshot = Process()
    screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    screenshot.arguments = ["-x", output.appendingPathComponent("screen.png").path]
    try screenshot.run()
    screenshot.waitUntilExit()
    guard screenshot.terminationStatus == 0 else { throw DriverError.failure("screencapture failed") }

    try writeJSON([
        "platform": "macos",
        "actions": [
            "type:quick-add", "press:quick-add-submit",
            "edit:escape-cancel", "edit:return-commit",
            "context-menu:delete", "press:undo-delete",
            "press:\(completionIdentifier)",
        ],
        "assertions": [
            "packaged SwiftUI window activated",
            "stable AXIdentifiers exposed",
            "RPC-created task appeared",
            "Escape cancelled the focused inline draft and visible Save/Cancel actions were exposed",
            "visible Save acknowledged and committed the inline draft",
            "Return committed a subsequent inline draft",
            "delete undo restored the original task ID",
            "changed Event removed the completed task from the active view",
            "native application accepted termination",
        ],
    ], to: output.appendingPathComponent("interaction-trace.json"))

    guard let running = NSRunningApplication(processIdentifier: pid), running.terminate() else {
        throw DriverError.failure("native application rejected termination")
    }
} catch {
    if let application = diagnosticApplication, let output = diagnosticOutput {
        try? writeJSON(snapshot(application), to: output.appendingPathComponent("accessibility-failure.json"))
    }
    FileHandle.standardError.write(Data("Taskly macOS acceptance failed: \(error)\n".utf8))
    exit(1)
}
