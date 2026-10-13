import AppKit
import CryptoKit
import Foundation

/// Online update service (shared/spec/UPDATE.md). Feed: the single
/// self-contained signed manifest wrapper (update-manifest.json — schema +
/// base64 payload + Ed25519 signature block, the family format the backend
/// verifies via rivet/distribution); install: zip → sha256 → ditto →
/// atomic in-place swap of the running bundle.
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
        "https://github.com/turinglambdaai/taskly/releases/latest/download/update-manifest.json")!
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

    /// The signed wrapper: the inner manifest travels base64-encoded so the
    /// Ed25519 signature covers the exact bytes every client verifies
    /// (rivet/distribution's signed-wrapper format).
    struct SignedWrapper: Decodable {
        struct SignatureBlock: Decodable {
            let algorithm: String
            let keyId: String
            let value: String
        }
        let schema: Int
        let payload: String
        let signature: SignatureBlock
    }

    public struct Manifest: Decodable, Sendable {
        public struct Artifact: Decodable, Sendable {
            let platform: String
            let architecture: String
            let url: URL
            let sha256: String
            let size: Int
        }
        let version: String
        let artifacts: [Artifact]

        /// The release feed carries one artifact per platform × architecture;
        /// each built host targets exactly one architecture, so the match is
        /// compile-time ("x64" on Intel builds, "arm64" on Apple silicon).
        nonisolated static let hostArchitecture: String = {
            #if arch(x86_64)
            return "x64"
            #elseif arch(arm64)
            return "arm64"
            #else
            #error("unsupported macOS architecture")
            #endif
        }()

        func artifact(forPlatform platform: String) -> Artifact? {
            artifacts.first { $0.platform == platform
                && $0.architecture == Self.hostArchitecture }
        }
    }

    private let i18n: I18nService
    private var session: URLSession
    /// Manifest endpoint; injectable only for tests (URLProtocol stubs)
    /// — production callers use the default.
    private let feedURL: URL
    /// Test seams for the runtime environment; nil = derive from Bundle.main.
    private let injectedBundleURL: URL?
    private let injectedCurrentVersion: String?
    /// Test-only embedded-key override (release env signs with the real key).
    nonisolated private let injectedKeyBase64: String?

    /// Removes swap work dirs older than 30 minutes — the swap script
    /// cannot reliably delete its own directory while bash is still
    /// reading it, so a later launch sweeps the leftovers.
    nonisolated public static func sweepStaleWorkDirs() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let base = fm.temporaryDirectory
        guard let names = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in names where url.lastPathComponent.hasPrefix("taskly-update-") {
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate, date < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    init(i18n: I18nService = .shared, feedURL: URL? = nil,
                bundleURL: URL? = nil, currentVersion: String? = nil,
                sessionConfiguration: URLSessionConfiguration? = nil,
                keyOverride: String? = nil) {
        self.i18n = i18n
        let config = sessionConfiguration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
        self.feedURL = feedURL ?? Self.manifestURL
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
        guard let (data, response) = try? await session.data(from: feedURL) else {
            throw UpdateError.network(i18n.t("updateCheckFailed"))
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try Self.verifyManifest(data, keyBase64: injectedKeyBase64)
    }

    // MARK: - Pure steps (unit-tested)

    /// Verifies the signed wrapper (schema, key id, Ed25519 over the exact
    /// payload bytes) and decodes the inner manifest.
    nonisolated static func verifyManifest(_ wrapperBytes: Data,
                                           keyBase64: String? = nil) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let wrapper: SignedWrapper
        do {
            wrapper = try decoder.decode(SignedWrapper.self, from: wrapperBytes)
        } catch {
            throw UpdateError.manifestMissing
        }
        guard wrapper.schema == 1 else { throw UpdateError.manifestMissing }
        guard wrapper.signature.algorithm == "ed25519",
              wrapper.signature.keyId == expectedKeyID else {
            throw UpdateError.signatureInvalid
        }
        guard let payload = Data(base64Encoded: wrapper.payload),
              let signature = Data(base64Encoded: wrapper.signature.value) else {
            throw UpdateError.signatureInvalid
        }
        guard signature.count == 64 else { throw UpdateError.signatureInvalid }
        guard let keyData = Data(base64Encoded: keyBase64 ?? publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw UpdateError.badPublicKey
        }
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw UpdateError.signatureInvalid
        }
        do {
            return try decoder.decode(Manifest.self, from: payload)
        } catch {
            throw UpdateError.network("manifest unparsable")
        }
    }

    // MARK: - Download + install

    /// Downloads, verifies (sha256, then unpacked bundle version), swaps the
    /// bundle in place and relaunches. Throws before touching the running
    /// install when anything is off. `onProgress` reports download percent
    /// (0…100) on the main actor for the update sheet.
    public func downloadAndInstall(_ manifest: Manifest,
                                   onProgress: (@Sendable (Int) -> Void)? = nil) async throws {
        guard let bundleURL = installedBundleURL else { throw UpdateError.notInstalled }
        guard let artifact = manifest.artifact(forPlatform: "macos") else {
            throw UpdateError.manifestMissing
        }
        try await Self.downloadAndSwap(artifact: artifact,
                                       bundleURL: bundleURL,
                                       expectedVersion: manifest.version,
                                       onProgress: onProgress ?? { _ in })
    }

    /// The whole download → verify → swap sequence, deliberately off the
    /// main actor so the transfer never competes with UI work.
    nonisolated private static func downloadAndSwap(
        artifact: Manifest.Artifact,
        bundleURL: URL,
        expectedVersion: String,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws {
        // Download to a temp directory.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskly-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zipURL = workDir.appendingPathComponent("taskly-update.zip")
        var swapLaunched = false
        defer {
            // Once the swap script is spawned it owns the work dir (it
            // unpacks from there after we are gone); deleting it here
            // would race the script's sleep and destroy the payload.
            if !swapLaunched { try? FileManager.default.removeItem(at: workDir) }
        }

        // Download via a delegate-driven download task. Byte-iterating
        // AsyncBytes can park its continuation forever when the stream's
        // end-of-stream flag never surfaces (observed live against the
        // GitHub CDN — all bytes delivered, the loop never wakes, the
        // sheet sticks at 100%, issue #13); the delegate's
        // didFinishDownloadingTo / didCompleteWithError are definitive,
        // and the request/resource timeout intervals bound a silent
        // stall. Task cancellation invalidates the session, so a
        // cancelled install always resumes promptly.
        let downloader = ArtifactDownloader(destination: zipURL,
                                            expectedSize: artifact.size,
                                            onProgress: onProgress)
        do {
            try await downloader.run(from: artifact.url)
        } catch let error as UpdateError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        // Size and sha256 against the signed manifest — from the file on
        // disk, so the artifact never sits whole in memory.
        let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        guard let fileSize = attributes[.size] as? Int, fileSize == artifact.size else {
            throw UpdateError.checksumMismatch
        }
        let digest = try Self.sha256Hex(ofFileAt: zipURL)
        guard digest == artifact.sha256.lowercased() else {
            throw UpdateError.checksumMismatch
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
        guard let newVersion = Bundle(url: newBundle)?
            .infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw UpdateError.versionMismatch(expected: expectedVersion, got: "missing")
        }
        guard newVersion == expectedVersion else {
            throw UpdateError.versionMismatch(expected: expectedVersion, got: newVersion)
        }

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
        do {
            try bash.run()
            swapLaunched = true
        } catch {
            throw error
        }
        await MainActor.run {
            // A presented SwiftUI sheet vetoes NSApplication.terminate
            // silently; end every sheet first so the quit sequence runs.
            for window in NSApplication.shared.windows {
                for sheet in window.sheets {
                    window.endSheet(sheet)
                }
            }
            NSApplication.shared.terminate(nil)
        }
        // If terminate was still vetoed (or deferred), stop the run loop
        // so the app leaves inside the swap script's sleep window — the
        // script waits out the single-instance lease before relaunching.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run { NSApplication.shared.stop(nil) }
    }

    nonisolated private static func q(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Chunked sha256 over a file on disk (the artifact is ~30 MB; hashing
    /// by 1 MiB chunks keeps peak memory flat).
    nonisolated private static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }


    /// One-artifact file download driven by URLSessionDownloadDelegate.
    /// Delegate callbacks arrive on the session's serial delegate queue;
    /// the checked continuation is taken exactly once under the lock.
    /// `finishTasksAndInvalidate` on completion also breaks the delegate
    /// retain cycle (the session retains its delegate).
    private nonisolated final class ArtifactDownloader: NSObject,
            URLSessionDownloadDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var lastPercent = -1
        private let destination: URL
        private let expectedSize: Int
        private let onProgress: @Sendable (Int) -> Void
        // Set once in init after super.init (the session needs self as its
        // delegate); never reassigned afterwards.
        private var session: URLSession!
        init(destination: URL, expectedSize: Int,
             onProgress: @escaping @Sendable (Int) -> Void) {
            self.destination = destination
            self.expectedSize = expectedSize
            self.onProgress = onProgress
            super.init()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }

        func run(from url: URL) async throws {
            let operation: @Sendable () async throws -> Void = { [self] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    begin(cont, url: url)
                }
            }
            let onCancel: @Sendable () -> Void = { [self] in
                session.invalidateAndCancel()
            }
            try await withTaskCancellationHandler(operation: operation,
                                                  onCancel: onCancel)
        }

        private func begin(_ cont: CheckedContinuation<Void, Error>, url: URL) {
            lock.lock()
            if continuation != nil {
                lock.unlock()
                cont.resume(throwing: UpdateError.network("download already running"))
                return
            }
            continuation = cont
            lock.unlock()
            session.downloadTask(with: url).resume()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            // Content-Length from the CDN; the signed manifest size is the
            // fallback when the response carries none.
            let total = totalBytesExpectedToWrite > 0
                ? Int(totalBytesExpectedToWrite) : max(expectedSize, 1)
            let percent = min(100, Int(totalBytesWritten) * 100 / total)
            if percent != lastPercent {
                lastPercent = percent
                onProgress(percent)
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // `location` is valid only inside this callback — move now.
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                resume(with: .success(()))
            } catch {
                resume(with: .failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            // Success is reported by didFinishDownloadingTo; this callback
            // carries the failure half (including cancellation and the
            // request/resource timeouts that bound a silent stall).
            guard let error else { return }
            resume(with: .failure(error))
        }

        private func resume(with result: Result<Void, Error>) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            session.finishTasksAndInvalidate()
            cont?.resume(with: result)
        }
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
