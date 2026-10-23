import Foundation

/// Parses a target list file (`.txt` / `.csv`) into a deduplicated set of IPv4 addresses.
/// Each non-blank, non-comment line may contain comma-separated IPs, CIDRs or `a-b` ranges.
public enum TargetFileParser {
    public struct Result: Sendable {
        public let targets: [String]
        public let invalidLines: [InvalidLine]
        public let parsedTokenCount: Int
    }

    public struct InvalidLine: Equatable, Sendable {
        public let lineNumber: Int
        public let content: String
    }

    public enum ParseError: Error, LocalizedError {
        case unreadable(URL)
        case noTargets

        public var errorDescription: String? {
            switch self {
            case .unreadable(let url): "Impossible de lire \(url.lastPathComponent)."
            case .noTargets: "Le fichier ne contient aucune adresse IP, CIDR ou plage valide."
            }
        }
    }

    public static func parse(url: URL) throws -> Result {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            throw ParseError.unreadable(url)
        }
        return parse(text: text)
    }

    /// Hard cap on total addresses this parser will expand into memory, enforced token by token.
    public static let maxAddresses = 65_536

    public static func parse(text: String) -> Result {
        var seen = Set<UInt32>()
        var invalid: [InvalidLine] = []
        var parsedTokenCount = 0

        outer: for (idx, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let tokens = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for token in tokens where !token.isEmpty {
                if let ipInt = IPv4.uint32(from: token) {
                    seen.insert(ipInt)
                    parsedTokenCount += 1
                } else if let range = ScanRange.parse(token) {
                    if range.upperBound >= range.lowerBound {
                        guard range.hostCount <= maxAddresses, seen.count + range.hostCount <= maxAddresses else {
                            invalid.append(InvalidLine(lineNumber: idx + 1, content: token))
                            continue
                        }
                        for v in range.lowerBound...range.upperBound { seen.insert(v) }
                    }
                    parsedTokenCount += 1
                } else {
                    invalid.append(InvalidLine(lineNumber: idx + 1, content: token))
                }
            }
            if seen.count > maxAddresses { break outer }
        }

        let targets = seen.sorted().map(IPv4.string(from:))
        return Result(targets: targets, invalidLines: invalid, parsedTokenCount: parsedTokenCount)
    }
}
