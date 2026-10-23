import Foundation

/// Offline IEEE registry (MA-L 24-bit, MA-M 28-bit, MA-S 36-bit) packed in `Resources/vendors.json`.
/// Loaded on first use; `shared` is safe to touch from any thread.
public final class OUILookup: @unchecked Sendable {
    public static let shared = OUILookup()

    private let mal: [String: String]   // 24-bit prefixes (6 hex chars)
    private let mam: [String: String]   // 28-bit prefixes (7 hex chars)
    private let mas: [String: String]   // 36-bit prefixes (9 hex chars)
    private let databaseAvailable: Bool

    private struct Registry: Decodable {
        let version: Int
        let mal: [String: String]
        let mam: [String: String]
        let mas: [String: String]
    }

    private init() {
        if let data = Self.loadData("vendors", ext: "json"),
           let registry = try? JSONDecoder().decode(Registry.self, from: data),
           registry.version == 1, !registry.mal.isEmpty, !registry.mam.isEmpty, !registry.mas.isEmpty {
            mas = registry.mas; mam = registry.mam; mal = registry.mal
            databaseAvailable = true
        } else {
            mas = [:]; mam = [:]; mal = [:]
            databaseAvailable = false
        }
    }

    /// Test-only initializer that bypasses the bundled registry.
    public init(mas: [String: String], mam: [String: String], mal: [String: String]) {
        self.mas = mas
        self.databaseAvailable = true
        self.mam = mam
        self.mal = mal
    }

    public var isAvailable: Bool { databaseAvailable }
    public var entryCount: Int { mal.count + mam.count + mas.count }

    public func resolve(_ raw: String?) -> VendorResolution {
        guard let raw else { return .init(vendor: nil, status: .macUnavailable) }
        guard let mac = MACAddress(raw) else { return .init(vendor: nil, status: .invalidAddress) }
        switch mac.kind {
        case .local: return .init(vendor: nil, status: .localAddress)
        case .multicast, .broadcast: return .init(vendor: nil, status: .nonUnicast)
        case .universal: break
        }
        guard databaseAvailable else { return .init(vendor: nil, status: .databaseUnavailable) }
        let key = mac.hex
        let vendor = mas[String(key.prefix(9))] ?? mam[String(key.prefix(7))] ?? mal[String(key.prefix(6))]
        return .init(vendor: vendor, status: vendor == nil ? .notFound : .matched)
    }

    public func vendor(forMAC mac: String) -> String? { resolve(mac).vendor }
    public static func normalizedHex(_ mac: String) -> String { MACAddress(mac)?.hex ?? "" }

    // MARK: - IEEE text parsers (kept for tests and for regenerating the index)

    static func parseMAL(content: String) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(40_000)
        for line in content.split(whereSeparator: \.isNewline) {
            guard let marker = line.range(of: "(hex)") else { continue }
            let prefix = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "-", with: "").uppercased()
            let vendor = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            guard validHex(prefix, length: 6), !vendor.isEmpty else { continue }
            result[prefix] = vendor
        }
        return result
    }

    static func parseSubBlock(content: String, subPrefixHexLength: Int) -> [String: String] {
        guard subPrefixHexLength == 1 || subPrefixHexLength == 3 else { return [:] }
        var result: [String: String] = [:]
        var lastOUI: String?
        for line in content.split(whereSeparator: \.isNewline) {
            if let marker = line.range(of: "(hex)") {
                let prefix = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "-", with: "").uppercased()
                lastOUI = validHex(prefix, length: 6) ? prefix : nil
            } else if let marker = line.range(of: "(base 16)"), let oui = lastOUI {
                let bounds = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                    .uppercased().split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2, validHex(String(bounds[0]), length: 6),
                      validHex(String(bounds[1]), length: 6) else { continue }
                let vendor = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                if !vendor.isEmpty { result[oui + bounds[0].prefix(subPrefixHexLength)] = vendor }
            }
        }
        return result
    }

    private static func validHex(_ string: String, length: Int) -> Bool {
        string.utf8.count == length && string.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0)
        }
    }

    private static func loadData(_ name: String, ext: String) -> Data? {
        for url in candidateURLs(for: name, ext: ext) {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    /// Where `vendors.json` may live: the app bundle (`Scripts/bundle.sh` copies it to
    /// `Contents/Resources`), the SwiftPM resource bundle next to a `swift run` binary,
    /// and the source tree for `swift test`. Never traps, unlike `Bundle.module`.
    private static func candidateURLs(for name: String, ext: String) -> [URL] {
        var urls: [URL] = []
        let fileName = "\(name).\(ext)"
        let bundleName = "SimpleScannerCore_SimpleScannerCore.bundle"
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { urls.append(url) }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)/\(fileName)"))
        let exeDir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().deletingLastPathComponent()
        urls.append(exeDir.appendingPathComponent("\(bundleName)/\(fileName)"))
        urls.append(exeDir.deletingLastPathComponent().appendingPathComponent("Resources/\(fileName)"))
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/\(fileName)"))
        return urls
    }
}
