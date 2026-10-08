import AppKit
import CryptoKit
import Foundation

/// Online update service (shared/spec/UPDATE.md). Feed: update-manifest.json
/// + Ed25519 signature from the latest GitHub Release; install: zip →
/// sha256 → ditto → atomic in-place swap of the running bundle.
///
/// Only a copy under /Applications (or ~/Applications) can self-update —
/// debug builds and random folders get the "not installed" answer.
@MainActor
public final class UpdateService {
    /// Ed25519 public key (base64, raw 32 bytes) — pair of the
    /// UPDATE_ED25519_PRIVATE_KEY GitHub secret that signs release
    /// manifests (generate: scripts/update-keys.sh).
    nonisolated public static let publicKeyBase64 = "lgCdBU0qFDNgamTJBIVX2jjPzehbTmCp3eV5ViubtF0="

    public static let releasesAPI = "https://api.github.com/repos/turinglambdaai/taskly/releases/latest"
    public static let releasesPage = "https://github.com/turinglambdaai/taskly/releases/latest"

    public enum UpdateError: LocalizedError {        case notInstalled
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

    public struct Manifest: Decodable {
        struct PlatformArtifact: Decodable {
            let url: URL
            let sha256: String
            let size: Int
        }
        let version: String
        let notesUrl: String
        let platforms: [String: PlatformArtifact]
    }

    private let i18n: I18nService
    private var session: URLSession
    /// Releases API endpoint; injectable only for tests (URLProtocol stubs)
    /// — production callers use the default.
    private let apiURL: URL
    /// Test seams for the runtime environment; nil = derive from Bundle.main.
    private let injectedBundleURL: URL?
    private let injectedCurrentVersion: String?
    /// Test-only embedded-key override (release env signs with the real key).
    nonisolated private let injectedKeyBase64: String?

    public init(i18n: I18nService = .shared, apiURL: URL? = nil,
                bundleURL: URL? = nil, currentVersion: String? = nil,
                sessionConfiguration: URLSessionConfiguration? = nil,
                keyOverride: String? = nil) {
        self.i18n = i18n
        let config = sessionConfiguration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
        self.apiURL = apiURL ?? URL(string: Self.releasesAPI)!
        self.injectedBundleURL = bundleURL
        self.injectedCurrentVersion = currentVersion
        self.injectedKeyBase64 = keyOverride
    }

    // MARK: - Environment

    /// The installed bundle this copy can update in place, or nil for
    /// development copies (not under /Applications or ~/Applications).
    public var installedBundleURL: URL? {
        if let injectedBundleURL { return injectedBundleURL }
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app"), path.hasPrefix("/Applications/")
            || path.hasPrefix("/Users/") && path.contains("/Applications/") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    public var canUpdate: Bool { installedBundleURL != nil }

    private var currentVersion: String {
        injectedCurrentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0"
    }

    // MARK: - Check

    /// Result of a completed check.
    public enum CheckResult {
        case upToDate
        case available(Manifest)
    }

    /// Fetches the latest release manifest, verifies its Ed25519 signature
    /// and compares versions. Throws with a precise reason otherwise
    /// (presentation — silent swallow vs error dialog — is the caller's job).
    public func check() async throws -> CheckResult {
        guard installedBundleURL != nil else {
            throw UpdateError.notInstalled
        }
        let manifest = try await fetchSignedManifest()
        if Self.isVersion(manifest.version, greaterThan: currentVersion) {
            return .available(manifest)
        }
        return .upToDate
    }

    private func fetchSignedManifest() async throws -> Manifest {
        guard let (data, response) = try? await session.data(from: apiURL) else {
            throw UpdateError.network(i18n.t("updateCheckFailed"))
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let assets = try Self.parseReleaseAssets(data)
        guard let manifestAsset = assets.manifest, let sigAsset = assets.signature else {
            throw UpdateError.manifestMissing
        }

        let (manifestBytes, mResponse) = try await session.data(from: manifestAsset)
        guard (mResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.network("manifest download failed")
        }
        let (sigBytes, sResponse) = try await session.data(from: sigAsset)
        guard (sResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.network("signature download failed")
        }
        return try Self.verifyManifest(manifestBytes, signature: sigBytes,
                                       keyBase64: injectedKeyBase64)
    }

    // MARK: - Pure steps (unit-tested)

    /// Extracts the download URLs of update-manifest.json / manifest.sig
    /// from a GitHub `releases/latest` API response.
    nonisolated static func parseReleaseAssets(_ apiResponse: Data) throws
        -> (manifest: URL?, signature: URL?) {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let assets: [Asset]
        }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: apiResponse)
        } catch {
            throw UpdateError.network("release metadata unparsable")
        }
        return (release.assets.first { $0.name == "update-manifest.json" }?.browser_download_url,
                release.assets.first { $0.name == "manifest.sig" }?.browser_download_url)
    }

    /// Ed25519 verification over the exact manifest bytes, then decode.
    nonisolated static func verifyManifest(_ manifestBytes: Data, signature: Data,
                                           keyBase64: String? = nil) throws -> Manifest {
        guard signature.count == 64 else { throw UpdateError.signatureInvalid }
        guard let keyData = Data(base64Encoded: keyBase64 ?? publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw UpdateError.badPublicKey
        }
        guard publicKey.isValidSignature(signature, for: manifestBytes) else {
            throw UpdateError.signatureInvalid
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: manifestBytes)
        } catch {
            throw UpdateError.network("manifest unparsable")
        }
    }

    // MARK: - Download + install

    /// Downloads, verifies (sha256, then unpacked bundle version), swaps the
    /// bundle in place and relaunches. Throws before touching the running
    /// install when anything is off.
    public func downloadAndInstall(_ manifest: Manifest) async throws {
        guard let bundleURL = installedBundleURL else { throw UpdateError.notInstalled }
        guard let artifact = manifest.platforms["macos"] else {
            throw UpdateError.manifestMissing
        }

        // Download to a temp directory.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskly-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zipURL = workDir.appendingPathComponent("taskly-update.zip")
        defer { try? FileManager.default.removeItem(at: workDir) }

        do {
            let (bytes, response) = try await session.bytes(from: artifact.url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.network("artifact download failed")
            }
            var hasher = SHA256()
            var data = Data()
            data.reserveCapacity(artifact.size)
            for try await byte in bytes {
                hasher.update(data: [byte])
                data.append(byte)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == artifact.sha256.lowercased() else {
                throw UpdateError.checksumMismatch
            }
            try data.write(to: zipURL)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        // Unzip and verify the payload really is the promised version.
        let unpacked = workDir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.checksumMismatch }

        let newBundle = unpacked.appendingPathComponent("Taskly.app")
        let newInfoPlist = newBundle.appendingPathComponent("Contents/Info.plist")
        guard let newVersion = Bundle(url: newBundle)?
            .infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw UpdateError.versionMismatch(expected: manifest.version, got: "missing")
        }
        guard newVersion == manifest.version else {
            throw UpdateError.versionMismatch(expected: manifest.version, got: newVersion)
        }
        _ = newInfoPlist

        // Swap: the shell script survives our exit; it also restores the
        // old bundle if the new one fails to move in. ~/.taskly is never
        // touched (UPDATE.md rollout rules).
        let old = bundleURL.path + ".old"
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf \(Self.q(old))
        if mv \(Self.q(bundleURL.path)) \(Self.q(old)); then
          if mv \(Self.q(newBundle.path)) \(Self.q(bundleURL.path)); then
            open \(Self.q(bundleURL.path))
            rm -rf \(Self.q(old))
            exit 0
          fi
          mv \(Self.q(old)) \(Self.q(bundleURL.path))
        fi
        exit 1
        """
        let swapPath = workDir.appendingPathComponent("swap.sh")
        try script.write(to: swapPath, atomically: true, encoding: .utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", swapPath.path]
        try chmod.run()
        chmod.waitUntilExit()

        // Launch the swap, then leave through the normal exit path so
        // AppKit tears the app down cleanly; the script's sleep 1 gives us
        // time to quit before it moves the bundle.
        let bash = Process()
        bash.executableURL = URL(fileURLWithPath: "/bin/bash")
        bash.arguments = [swapPath.path]
        try bash.run()
        NSApplication.shared.terminate(nil)
    }

    private static func q(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Version compare (numeric per segment; 1.2 > 1.1.9)

    nonisolated public static func isVersion(_ a: String, greaterThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        let length = max(av.count, bv.count)
        for i in 0..<length {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
