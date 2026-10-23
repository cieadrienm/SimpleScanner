import Foundation

/// A contiguous IPv4 range typed by the user: a CIDR block, `a-b`, or a single address.
public struct ScanRange: Hashable, Sendable {
    public let displayString: String
    public let lowerBound: UInt32
    public let upperBound: UInt32

    public var addresses: [String] {
        guard upperBound >= lowerBound else { return [] }
        return (lowerBound...upperBound).map(IPv4.string(from:))
    }

    public var hostCount: Int { Int(upperBound) - Int(lowerBound) + 1 }

    public func contains(_ value: UInt32) -> Bool { value >= lowerBound && value <= upperBound }

    public static func parse(_ input: String) -> ScanRange? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let r = ScanRange(cidr: trimmed) { return r }
        if let r = ScanRange(range: trimmed) { return r }
        if let r = ScanRange(singleIP: trimmed) { return r }
        return nil
    }

    public init?(singleIP: String) {
        guard let value = IPv4.uint32(from: singleIP) else { return nil }
        self.lowerBound = value
        self.upperBound = value
        self.displayString = singleIP
    }

    /// Parses comma-separated input into multiple ranges.
    /// Returns the parsed list and the index (1-based) of the first invalid chunk, if any.
    public static func parseAll(_ input: String) -> (ranges: [ScanRange], firstInvalidIndex: Int?) {
        let chunks = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var ranges: [ScanRange] = []
        for (idx, chunk) in chunks.enumerated() where !chunk.isEmpty {
            guard let r = parse(chunk) else {
                return (ranges, idx + 1)
            }
            ranges.append(r)
        }
        return (ranges, nil)
    }

    /// Total host count across ranges, computed WITHOUT expanding any address list.
    public static func totalHostCount(_ ranges: [ScanRange]) -> Int {
        ranges.reduce(0) { partial, r in
            let count = r.upperBound >= r.lowerBound ? r.hostCount : 0
            let (sum, overflow) = partial.addingReportingOverflow(count)
            return overflow ? Int.max : sum
        }
    }

    /// Combined unique addresses from multiple ranges, sorted numerically.
    public static func uniqueAddresses(_ ranges: [ScanRange]) -> [String] {
        var seen = Set<UInt32>()
        seen.reserveCapacity(ranges.reduce(0) { $0 + $1.hostCount })
        for r in ranges where r.upperBound >= r.lowerBound {
            for v in r.lowerBound...r.upperBound { seen.insert(v) }
        }
        return seen.sorted().map(IPv4.string(from:))
    }

    public init?(cidr: String) {
        guard let slash = cidr.firstIndex(of: "/") else { return nil }
        let ipPart = String(cidr[..<slash])
        let prefixPart = String(cidr[cidr.index(after: slash)...])
        guard let prefix = Int(prefixPart), (0...32).contains(prefix) else { return nil }
        guard let ipInt = IPv4.uint32(from: ipPart) else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = ipInt & mask
        let broadcast = network | ~mask

        if prefix < 31 {
            self.lowerBound = network &+ 1
            self.upperBound = broadcast == 0 ? 0 : broadcast &- 1
        } else {
            self.lowerBound = network
            self.upperBound = broadcast
        }
        self.displayString = cidr
    }

    public init?(range: String) {
        let parts = range.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lo = IPv4.uint32(from: parts[0]),
              let hi = IPv4.uint32(from: parts[1]),
              lo <= hi else { return nil }
        self.lowerBound = lo
        self.upperBound = hi
        self.displayString = range
    }
}

public enum IPv4 {
    public static func uint32(from ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        return result
    }

    public static func string(from value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// RFC 1918 private ranges, loopback and link-local.
    public static func isPrivate(_ ip: String) -> Bool {
        guard let v = uint32(from: ip) else { return false }
        let a = v >> 24, b = (v >> 16) & 0xFF
        if a == 10 || a == 127 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        if a == 169, b == 254 { return true }
        return false
    }
}
