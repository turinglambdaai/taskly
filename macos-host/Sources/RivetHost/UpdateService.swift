import Foundation
import RivetUpdate

/// Online update service (shared/spec/UPDATE.md) — a thin product adapter
/// over rivet's `RivetUpdate` module (the family's shared host-side update
/// client since rivet 0.8.1): this file only contributes the product facts
/// (feed, signing key, key id, bundle name), the localized error surface,
/// and the seams future host tests may want. Verification, the bounded
/// delegate-driven download, the atomic swap with rollback, and the
/// quit/relaunch handoff all live in the library.
///
/// Only a copy under /Applications (or ~/Applications) can self-update —
/// debug builds and random folders get the "not installed" answer.
@MainActor
public final class UpdateService {
    /// Ed25519 public key (base64, raw 32 bytes) — pair of the
    /// UPDATE_ED25519_PRIVATE_KEY GitHub secret that signs release
    /// manifests (generate: scripts/update-keys.sh).
    nonisolated public static let publicKeyBase64 = "lgCdBU0qFDNgamTJBIVX2jjPzehbTmCp3eV5ViubtF0="

    /// The manifest must carry this key id — rotation ships a build that
    /// trusts the next key before releases stop being signed with this one.
    nonisolated public static let expectedKeyID = "taskly-2026-10"

    public static let manifestURL = URL(string:
        "https://github.com/turlamai/taskly/releases/latest/download/update-manifest.json")!
    public static let releasesPage = "https://github.com/turlamai/taskly/releases/latest"

    public enum UpdateError: LocalizedError {
        case notInstalled
        case badPublicKey
        case manifestMissing
        case signatureInvalid
        case checksumMismatch
        case versionMismatch(expected: String, got: String)
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled: return "not an installed app bundle"
            case .badPublicKey: return "embedded public key is invalid"
            case .manifestMissing: return "release has no update manifest"
            case .signatureInvalid: return "manifest signature check failed"
            case .checksumMismatch: return "downloaded archive failed the sha256 check"
            case .versionMismatch(let expected, let got): return "bundle version \(got) ≠ manifest \(expected)"
            case .network(let message): return message
            }
        }
    }

    public typealias Manifest = RivetUpdateManifest

    public enum CheckResult {
        case upToDate
        case available(Manifest)
    }

    private let i18n: I18nService
    /// nil only when the (constant) product configuration failed the
    /// library's fail-closed validation — surfaced as badPublicKey.
    private let service: RivetUpdateService?

    init(i18n: I18nService = .shared, feedURL: URL? = nil,
                bundleURL: URL? = nil, currentVersion: String? = nil,
                sessionConfiguration: URLSessionConfiguration? = nil,
                keyOverride: String? = nil) {
        self.i18n = i18n
        let configuration = RivetUpdateConfiguration(
            feedURL: feedURL ?? Self.manifestURL,
            publicKeyBase64: keyOverride ?? Self.publicKeyBase64,
            keyID: Self.expectedKeyID,
            bundleName: "Taskly.app")
        self.service = try? RivetUpdateService(
            configuration: configuration,
            bundlePath: bundleURL?.path,
            currentVersion: currentVersion,
            sessionConfiguration: sessionConfiguration)
    }

    /// Translates library errors into this product's (localized) surface.
    nonisolated private static func map(_ error: RivetUpdateError) -> UpdateError {
        switch error {
        case .notInstalled: return .notInstalled
        case .badPublicKey: return .badPublicKey
        case .invalidConfiguration: return .badPublicKey
        case .manifestMissing: return .manifestMissing
        case .signatureInvalid: return .signatureInvalid
        case .checksumMismatch: return .checksumMismatch
        case .sizeMismatch: return .checksumMismatch
        case .versionMismatch(let expected, let got):
            return .versionMismatch(expected: expected, got: got)
        case .network(let message): return .network(message)
        }
    }

    /// Removes swap work dirs older than 30 minutes — the swap script
    /// cannot reliably delete its own directory while bash is still
    /// reading it, so a later launch sweeps the leftovers.
    nonisolated public static func sweepStaleWorkDirs() {
        RivetUpdateService.cleanupStaleWorkDirectories(olderThan: 30 * 60)
    }

    // MARK: - Environment

    /// The installed bundle this copy can update in place, or nil for
    /// development copies (not under /Applications or ~/Applications).
    public var installedBundleURL: URL? { service?.installedBundleURL }

    public var canUpdate: Bool { service?.canUpdate ?? false }

    // MARK: - Check

    /// Fetches the latest release manifest, verifies its Ed25519 signature
    /// and compares versions. Throws with a precise reason otherwise
    /// (presentation — silent swallow vs error dialog — is the caller's job).
    public func check() async throws -> CheckResult {
        guard let service else { throw UpdateError.badPublicKey }
        do {
            switch try await service.check() {
            case .upToDate: return .upToDate
            case .available(let manifest): return .available(manifest)
            }
        } catch let error as RivetUpdateError {
            throw Self.map(error)
        }
    }

    // MARK: - Download + install

    /// Downloads, verifies (sha256, then unpacked bundle version), swaps the
    /// bundle in place and relaunches. Throws before touching the running
    /// install when anything is off. `onProgress` reports download percent
    /// (0…100) on a background thread for the update sheet.
    public func downloadAndInstall(_ manifest: Manifest,
                                   onProgress: (@Sendable (Int) -> Void)? = nil) async throws {
        guard let service else { throw UpdateError.badPublicKey }
        do {
            try await service.downloadAndInstall(manifest, onProgress: onProgress)
        } catch let error as RivetUpdateError {
            throw Self.map(error)
        }
    }

    // MARK: - Version compare (numeric per segment; 1.2 > 1.1.9)

    nonisolated public static func isVersion(_ a: String, greaterThan b: String) -> Bool {
        RivetUpdateService.isVersion(a, greaterThan: b)
    }
}
