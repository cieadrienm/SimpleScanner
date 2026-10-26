import AppKit
import CryptoKit
import Foundation
import Observation
import SimpleScannerCore

/// Lightweight, zero-dependency auto-updater for SimpleScanner.
/// Supports a custom JSON manifest URL or GitHub Releases API (`cieadrienm/SimpleScanner`),
/// SHA-256 verification via CryptoKit, `codesign` validation, and atomic app bundle replacement.
@Observable
@MainActor
final class SimpleUpdater {
    struct ReleaseInfo: Equatable, Sendable {
        let version: String
        let build: Int?
        let downloadURL: URL
        let sha256: String?
        let notesFR: String
        let notesEN: String
        let htmlURL: URL?

        init(
            version: String,
            build: Int? = nil,
            downloadURL: URL,
            sha256: String? = nil,
            notesFR: String = "",
            notesEN: String = "",
            htmlURL: URL? = nil
        ) {
            self.version = version
            self.build = build
            self.downloadURL = downloadURL
            self.sha256 = sha256
            self.notesFR = notesFR
            self.notesEN = notesEN
            self.htmlURL = htmlURL
        }

        var notes: String {
            let preferred = Localization.isEnglish ? notesEN : notesFR
            let fallback = Localization.isEnglish ? notesFR : notesEN
            let text = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : text
        }
    }

    enum State: Equatable, Sendable {
        case idle
        case checking
        case upToDate(String)
        case updateAvailable(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    enum UpdaterError: LocalizedError, Equatable {
        case invalidResponse(Int)
        case invalidManifest
        case noZipAssetFound
        case checksumMismatch(expected: String, actual: String)
        case extractionFailed(String)
        case appBundleNotFound
        case invalidCodeSignature(String)
        case teamIdentifierMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let code):
                return L("Réponse serveur invalide (HTTP \(code)).", "Invalid server response (HTTP \(code)).")
            case .invalidManifest:
                return L("Format de manifeste de mise à jour invalide.", "Invalid update manifest format.")
            case .noZipAssetFound:
                return L("Aucune archive .zip trouvée dans cette version.", "No .zip archive found in this release.")
            case .checksumMismatch(let expected, let actual):
                return L("Empreinte SHA-256 invalide (attendue : \(expected.prefix(12))…, reçue : \(actual.prefix(12))…).", "SHA-256 checksum mismatch (expected: \(expected.prefix(12))…, got: \(actual.prefix(12))…).")
            case .extractionFailed(let detail):
                return L("Échec de la décompression de l'archive : \(detail)", "Archive extraction failed: \(detail)")
            case .appBundleNotFound:
                return L("Aucune application (.app) trouvée dans l'archive.", "No application (.app) bundle found in archive.")
            case .invalidCodeSignature(let detail):
                return L("Signature de code invalide : \(detail)", "Invalid code signature: \(detail)")
            case .teamIdentifierMismatch(let expected, let actual):
                return L("Identifiant d'équipe incohérent (attendu : \(expected), reçu : \(actual)).", "Team identifier mismatch (expected: \(expected), got: \(actual)).")
            }
        }
    }

    nonisolated static let defaultRepo = "cieadrienm/SimpleScanner"
    nonisolated static let defaultBundleID = "net.cieadrienm.simplescanner"
    nonisolated static let autoCheckKey = "net.cieadrienm.simplescanner.autoCheckUpdates"
    nonisolated static let lastCheckKey = "net.cieadrienm.simplescanner.lastUpdateCheckTimestamp"
    nonisolated static let updateURLKey = "net.cieadrienm.simplescanner.updateURL"
    nonisolated static let infoPlistUpdateURLKey = "SimpleUpdateURL"
    nonisolated static let envUpdateURLKey = "SIMPLE_UPDATE_URL"
    nonisolated static let checkInterval: TimeInterval = 86_400

    var state: State = .idle
    var autoCheckOnLaunch: Bool {
        didSet { defaults.set(autoCheckOnLaunch, forKey: Self.autoCheckKey) }
    }

    let repo: String
    let bundleID: String
    let currentVersion: String
    let currentBuild: Int?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dataFetcher: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    init(
        repo: String = SimpleUpdater.defaultRepo,
        bundleID: String = SimpleUpdater.defaultBundleID,
        currentVersion: String = AppVersion.current.version,
        currentBuild: Int? = AppVersion.current.build.flatMap(Int.init),
        defaults: UserDefaults = .standard,
        dataFetcher: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.repo = repo
        self.bundleID = bundleID
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.defaults = defaults
        self.dataFetcher = dataFetcher ?? { request in
            try await URLSession.shared.data(for: request)
        }
        if defaults.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckOnLaunch = true
        } else {
            self.autoCheckOnLaunch = defaults.bool(forKey: Self.autoCheckKey)
        }
    }

    // MARK: - Update Checking

    func checkOnLaunchIfNeeded(
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) {
        guard autoCheckOnLaunch else { return }
        guard !Self.isRunningHeadlessOrTests(environment: environment, arguments: arguments) else { return }
        let lastCheck = defaults.double(forKey: Self.lastCheckKey)
        guard now.timeIntervalSince1970 - lastCheck >= Self.checkInterval else { return }
        checkForUpdates(silent: true)
    }

    func checkForUpdates(silent: Bool = false) {
        checkTask?.cancel()
        checkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCheck(silent: silent)
        }
    }

    func performCheck(
        silent: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) async {
        if !silent {
            state = .checking
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

        do {
            let release: ReleaseInfo
            if let manifestURL = Self.customUpdateURL(environment: environment, defaults: defaults, infoDictionary: infoDictionary) {
                var request = URLRequest(url: manifestURL)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("SimpleScanner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await dataFetcher(request)
                try Self.validateHTTPResponse(response)
                release = try Self.parseManifest(data: data, bundleID: bundleID)
            } else {
                let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
                var request = URLRequest(url: apiURL)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("SimpleScanner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await dataFetcher(request)
                try Self.validateHTTPResponse(response)
                release = try Self.parseGitHubRelease(data: data)
            }

            guard !Task.isCancelled else { return }
            if Self.isNewerVersion(release.version, candidateBuild: release.build, than: currentVersion, currentBuild: currentBuild) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate(currentVersion)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if silent {
                if case .checking = state { state = .idle }
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Download & Install

    func downloadAndInstall(_ release: ReleaseInfo) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDownloadAndInstall(release)
        }
    }

    func performDownloadAndInstall(_ release: ReleaseInfo) async {
        state = .downloading(0.1)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleScannerUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            var request = URLRequest(url: release.downloadURL)
            request.timeoutInterval = 120
            request.setValue("SimpleScanner/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await dataFetcher(request)
            try Self.validateHTTPResponse(response)
            state = .downloading(0.85)

            let zipURL = tempDir.appendingPathComponent("update.zip")
            try data.write(to: zipURL, options: .atomic)

            if let expectedSHA = release.sha256?.trimmingCharacters(in: .whitespacesAndNewlines), !expectedSHA.isEmpty {
                let actualSHA = Self.sha256Hex(of: data)
                if actualSHA.lowercased() != expectedSHA.lowercased() {
                    throw UpdaterError.checksumMismatch(expected: expectedSHA, actual: actualSHA)
                }
            }

            state = .downloading(1.0)
            state = .installing

            let extractDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let newAppURL = try await Task.detached(priority: .userInitiated) {
                try Self.extractAndValidateApp(zipURL: zipURL, extractDir: extractDir, currentAppURL: Bundle.main.bundleURL)
            }.value

            let destPath: String
            if Bundle.main.bundleURL.pathExtension == "app" {
                destPath = Bundle.main.bundleURL.path
            } else {
                destPath = "/Applications/SimpleScanner.app"
            }

            try Self.spawnRelaunchHelper(newAppPath: newAppURL.path, destinationAppPath: destPath, tempDir: tempDir.path)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers & Validation

    static func customUpdateURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> URL? {
        let candidates: [String?] = [
            environment[envUpdateURLKey],
            defaults.string(forKey: updateURLKey),
            infoDictionary?[infoPlistUpdateURLKey] as? String
        ]
        for raw in candidates {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !trimmed.hasPrefix("@"),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" || scheme == "file" else {
                continue
            }
            return url
        }
        return nil
    }

    static func isRunningHeadlessOrTests(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return true
        }
        let headlessFlags: Set<String> = ["--self-test", "--scan", "--snapshot", "--version", "-v"]
        return arguments.dropFirst().contains { headlessFlags.contains($0) }
    }

    static func validateHTTPResponse(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdaterError.invalidResponse(http.statusCode)
        }
    }

    /// Compares semantic versions (`1.1.0` > `1.0.0`), falling back to `candidateBuild > currentBuild` when versions match.
    static func isNewerVersion(
        _ candidate: String,
        candidateBuild: Int? = nil,
        than current: String,
        currentBuild: Int? = nil
    ) -> Bool {
        let lhs = parseVersionComponents(candidate)
        let rhs = parseVersionComponents(current)
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        if let candidateBuild, let currentBuild {
            return candidateBuild > currentBuild
        }
        return false
    }

    static func normalizeVersionString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    private static func parseVersionComponents(_ version: String) -> [Int] {
        let clean = normalizeVersionString(version)
        let core = clean.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? clean
        return core.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    // MARK: - JSON Parsing

    /// Parses either a multi-app manifest keyed by `bundleID` or a single-app manifest object.
    static func parseManifest(data: Data, bundleID: String = defaultBundleID) throws -> ReleaseInfo {
        guard let topObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdaterError.invalidManifest
        }
        let entry: [String: Any]
        if let scoped = topObject[bundleID] as? [String: Any] {
            entry = scoped
        } else {
            entry = topObject
        }

        guard let rawVersion = entry["version"] as? String,
              !rawVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdaterError.invalidManifest
        }
        let urlString = (entry["url"] as? String) ?? (entry["download_url"] as? String)
        guard let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let downloadURL = URL(string: rawURL),
              downloadURL.scheme != nil else {
            throw UpdaterError.invalidManifest
        }

        let build: Int?
        if let intBuild = entry["build"] as? Int {
            build = intBuild
        } else if let strBuild = entry["build"] as? String {
            build = Int(strBuild.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            build = nil
        }

        let sha256 = (entry["sha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericNotes = (entry["notes"] as? String) ?? ""
        let notesFR = (entry["notes_fr"] as? String) ?? genericNotes
        let notesEN = (entry["notes_en"] as? String) ?? genericNotes
        let htmlURL = (entry["html_url"] as? String).flatMap(URL.init(string:))

        return ReleaseInfo(
            version: normalizeVersionString(rawVersion),
            build: build,
            downloadURL: downloadURL,
            sha256: (sha256?.isEmpty == false) ? sha256 : nil,
            notesFR: notesFR,
            notesEN: notesEN,
            htmlURL: htmlURL
        )
    }

    /// Parses a GitHub Releases API `/releases/latest` JSON payload.
    static func parseGitHubRelease(data: Data) throws -> ReleaseInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw UpdaterError.invalidManifest
        }
        let version = normalizeVersionString(tagName)
        guard !version.isEmpty else {
            throw UpdaterError.invalidManifest
        }
        let body = (json["body"] as? String) ?? ""
        let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))

        guard let assets = json["assets"] as? [[String: Any]] else {
            throw UpdaterError.noZipAssetFound
        }
        var foundURL: URL?
        var assetSHA256: String?
        for asset in assets {
            let name = (asset["name"] as? String) ?? ""
            let urlStr = (asset["browser_download_url"] as? String) ?? ""
            if name.lowercased().hasSuffix(".zip") || urlStr.lowercased().hasSuffix(".zip") {
                if let url = URL(string: urlStr) {
                    foundURL = url
                    if let digest = asset["digest"] as? String,
                       digest.lowercased().hasPrefix("sha256:") {
                        let hex = String(digest.dropFirst("sha256:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if hex.count == 64 { assetSHA256 = hex }
                    }
                    break
                }
            }
        }
        guard let downloadURL = foundURL else {
            throw UpdaterError.noZipAssetFound
        }

        let sha256 = assetSHA256 ?? extractSHA256FromText(body)
        return ReleaseInfo(
            version: version,
            build: nil,
            downloadURL: downloadURL,
            sha256: sha256,
            notesFR: body,
            notesEN: body,
            htmlURL: htmlURL
        )
    }

    private static func extractSHA256FromText(_ text: String) -> String? {
        let pattern = #"(?i)sha-?256\s*[:=]\s*([0-9a-f]{64})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).lowercased()
    }

    // MARK: - CryptoKit SHA-256

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256Hex(of: data)
    }

    static func verifySHA256(fileURL: URL, expectedHex: String?) throws -> Bool {
        guard let expected = expectedHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expected.isEmpty else {
            return true
        }
        let actual = try sha256Hex(ofFileAt: fileURL)
        return actual.lowercased() == expected.lowercased()
    }

    // MARK: - Extraction & Code Signing

    nonisolated private static func extractAndValidateApp(
        zipURL: URL,
        extractDir: URL,
        currentAppURL: URL
    ) throws -> URL {
        let dittoResult = runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractDir.path])
        guard dittoResult.exitCode == 0 else {
            throw UpdaterError.extractionFailed(dittoResult.stderr.isEmpty ? "ditto exit \(dittoResult.exitCode)" : dittoResult.stderr)
        }

        guard let newAppURL = findAppBundle(in: extractDir) else {
            throw UpdaterError.appBundleNotFound
        }

        let verifyResult = runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", newAppURL.path])
        guard verifyResult.exitCode == 0 else {
            throw UpdaterError.invalidCodeSignature(verifyResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if currentAppURL.pathExtension == "app",
           let currentTeam = teamIdentifier(forAppAt: currentAppURL.path),
           !currentTeam.isEmpty {
            let newTeam = teamIdentifier(forAppAt: newAppURL.path) ?? "none"
            if newTeam != currentTeam {
                throw UpdaterError.teamIdentifierMismatch(expected: currentTeam, actual: newTeam)
            }
        }

        return newAppURL
    }

    nonisolated private static func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        if let direct = items.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        for sub in items {
            if let subItems = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]),
               let nested = subItems.first(where: { $0.pathExtension == "app" }) {
                return nested
            }
        }
        return nil
    }

    nonisolated static func teamIdentifier(forAppAt path: String) -> String? {
        let res = runProcess("/usr/bin/codesign", arguments: ["-dv", "--verbose=4", path])
        let combined = res.stderr + "\n" + res.stdout
        for line in combined.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                let value = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if value != "not set" && !value.isEmpty {
                    return value
                }
                return nil
            }
        }
        return nil
    }

    nonisolated private static func runProcess(_ executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, stdout, stderr)
    }

    private static func spawnRelaunchHelper(newAppPath: String, destinationAppPath: String, tempDir: String) throws {
        let script = """
        sleep 0.6
        rm -rf "$DEST"
        ditto "$NEW_APP" "$DEST"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        open "$DEST"
        rm -rf "$TEMP_DIR" 2>/dev/null || true
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var env = ProcessInfo.processInfo.environment
        env["NEW_APP"] = newAppPath
        env["DEST"] = destinationAppPath
        env["TEMP_DIR"] = tempDir
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
