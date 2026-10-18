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

    let completion: AXUIElement = try waitFor("task completion control") {
        find(window, identifierPrefix: "task-complete-")
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
        "actions": ["type:quick-add", "press:quick-add-submit", "press:\(completionIdentifier)"],
        "assertions": [
            "packaged SwiftUI window activated",
            "stable AXIdentifiers exposed",
            "RPC-created task appeared",
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
