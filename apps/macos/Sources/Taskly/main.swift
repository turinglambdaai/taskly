// Entry point. CLI subcommands run before any AppKit/SwiftUI initialization
// (headless-safe, mirrors the dual-mode contract); no arguments → GUI.
import Foundation

let arguments = CommandLine.arguments
if arguments.count > 1 {
    let status = CliEngine.run(Array(arguments.dropFirst()))
    exit(status)
}

TasklyApp.main()
