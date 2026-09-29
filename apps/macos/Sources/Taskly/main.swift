// Entry point. CLI subcommands run before any AppKit/SwiftUI initialization
// (headless-safe, mirrors the dual-mode contract); no arguments → GUI.
import AppKit
import Foundation

let arguments = CommandLine.arguments
if arguments.count > 1 {
    let status = CliEngine.run(Array(arguments.dropFirst()))
    exit(status)
}

// Single-window app: window tabbing only adds system menu noise
// ("Show Tab Bar" et al.) that PRODUCT-SPEC §8 does not define.
NSWindow.allowsAutomaticWindowTabbing = false

TasklyApp.main()
