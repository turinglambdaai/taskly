import Foundation

/// Error with a user-facing message and a category. Categories map to CLI
/// exit codes (CLI-SPEC.md): validation→2, notFound→3, database→4, else→1.
public enum AppErrorType: Sendable, Hashable {
    case generic
    case validation
    case notFound
    case database
}

public struct AppError: Error, Sendable {
    public var message: String
    public var type: AppErrorType

    public init(_ message: String, _ type: AppErrorType = .generic) {
        self.message = message
        self.type = type
    }

    public var exitCode: Int32 {
        switch type {
        case .generic: return 1
        case .validation: return 2
        case .notFound: return 3
        case .database: return 4
        }
    }
}

/// Input validation. Messages are localized (i18n contract). Limits live in
/// ValidationHelper (Data/Config.swift); this file only carries the error type.
