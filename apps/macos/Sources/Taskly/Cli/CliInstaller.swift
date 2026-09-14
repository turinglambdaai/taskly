import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Installs/uninstalls the `taskly` command into ~/.local/bin (macOS/Linux).
public enum CliInstaller {
    public struct Result {
        public var message: String
        public var needsShellRestart: Bool
    }

    static var binDir: String { PathUtils.homeDirectory + "/.local/bin" }
    static var linkPath: String { binDir + "/taskly" }

    static var executablePath: String {
        let argv0 = CommandLine.arguments.first ?? "taskly"
        let url = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
        return url.path
    }

    @discardableResult
    public static func install() throws -> Int32 {
        let exe = executablePath

        if !FileManager.default.fileExists(atPath: binDir) {
            try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }

        let script = "#!/bin/sh\nexec \"\(exe)\" \"$@\"\n"
        try script.write(toFile: linkPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: linkPath)

        var needsRestart = false
        if !pathContainsBinDir() {
            needsRestart = ensurePathInShellRc()
        }

        print("taskly command installed to \(linkPath)")
        if needsRestart {
            print("\nPlease open a new terminal window for the PATH change to take effect.")
        }
        return 0
    }

    @discardableResult
    public static func uninstall() throws -> Int32 {
        guard FileManager.default.fileExists(atPath: linkPath) else {
            FileHandle.standardError.write(
                Data("taskly command was not installed (nothing to remove).\n".utf8))
            return 1
        }
        try FileManager.default.removeItem(atPath: linkPath)
        print("taskly command removed from \(linkPath)")
        return 0
    }

    static func pathContainsBinDir() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.components(separatedBy: ":").contains(binDir)
    }

    /// Appends an idempotent PATH block to ~/.zshrc (macOS) / ~/.bashrc (Linux).
    static func ensurePathInShellRc() -> Bool {
        let rcPath = PathUtils.homeDirectory + "/.zshrc"
        let marker = "# Added by Taskly"
        let content = FileManager.default.fileExists(atPath: rcPath)
            ? ((try? String(contentsOfFile: rcPath, encoding: .utf8)) ?? "")
            : ""

        if content.contains(marker) || content.contains(".local/bin") {
            return false
        }

        let block = "\n\(marker)\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"
        let updated = content.hasSuffix("\n") || content.isEmpty ? content + block : content + "\n" + block
        do {
            try updated.write(toFile: rcPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
