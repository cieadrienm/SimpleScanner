import Foundation

/// A saved scan (`.simplescan`, JSON inside). Older iPScanner `.ipscan.json` files decode too.
public struct ScanSnapshot: Codable, Sendable {
    public static let currentVersion = 1
    public static let fileExtension = "simplescan"
    public static let legacyFileExtension = "json"

    public let version: Int
    public let createdAt: Date
    public let rangeInput: String
    public let hosts: [HostRecord]
    public let labels: [String: String]

    public init(version: Int = ScanSnapshot.currentVersion, createdAt: Date, rangeInput: String, hosts: [HostRecord], labels: [String: String]) {
        self.version = version
        self.createdAt = createdAt
        self.rangeInput = rangeInput
        self.hosts = hosts
        self.labels = labels
    }

    public struct HostRecord: Codable, Equatable, Hashable, Sendable {
        public let ip: String
        public let hostname: String?
        public let mac: String?
        public let vendorStatus: VendorStatus?
        public let vendor: String?
        public let rttMs: Double?
        public let ttl: Int?
        public let netbiosName: String?
        public let workgroup: String?
        public let openPorts: [Int]
        public let serviceTitle: String?
        public let model: String?
        public let bonjourName: String?
        public let services: [String]
        public let role: Host.Role?
        public let status: Host.Status

        public init(ip: String, hostname: String?, mac: String?, vendor: String?, vendorStatus: VendorStatus? = nil,
                    rttMs: Double?, ttl: Int?, netbiosName: String? = nil,
                    workgroup: String? = nil, openPorts: [Int], serviceTitle: String?,
                    model: String? = nil, bonjourName: String? = nil, services: [String] = [],
                    role: Host.Role? = nil, status: Host.Status = .alive) {
            self.ip = ip
            self.hostname = hostname
            self.mac = mac
            self.vendor = vendor
            self.vendorStatus = vendorStatus
            self.rttMs = rttMs
            self.ttl = ttl
            self.netbiosName = netbiosName
            self.workgroup = workgroup
            self.openPorts = openPorts
            self.serviceTitle = serviceTitle
            self.model = model
            self.bonjourName = bonjourName
            self.services = services
            self.role = role
            self.status = status
        }

        public init(_ h: Host) {
            self.init(ip: h.ip, hostname: h.hostname, mac: h.mac, vendor: h.vendor, vendorStatus: h.vendorStatus,
                      rttMs: h.rttMs, ttl: h.ttl, netbiosName: h.netbiosName, workgroup: h.workgroup,
                      openPorts: h.openPorts, serviceTitle: h.serviceTitle, model: h.model,
                      bonjourName: h.bonjourName, services: h.services, role: h.role, status: h.status)
        }

        public func host(vendorStatus: VendorStatus? = .historical) -> Host {
            Host(ip: ip, hostname: hostname, mac: mac, vendor: vendor, vendorStatus: vendorStatus ?? self.vendorStatus,
                 rttMs: rttMs, ttl: ttl, netbiosName: netbiosName, workgroup: workgroup, openPorts: openPorts,
                 serviceTitle: serviceTitle, model: model, bonjourName: bonjourName, services: services, role: role, status: status)
        }

        // Custom decoder lets older files (no `ttl`, `netbiosName`, `model`, …) still load.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let ip = try c.decode(String.self, forKey: .ip)
            // Snapshot files can be hand-edited. The `ip` ends up in URLs and shell commands,
            // so a non-IPv4 value is rejected at decode time, not sanitized later.
            guard IPv4.uint32(from: ip) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .ip, in: c, debugDescription: "\"\(ip)\" n'est pas une adresse IPv4 valide"
                )
            }
            self.ip = ip
            self.hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
            self.mac = try c.decodeIfPresent(String.self, forKey: .mac)
            self.vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
            self.vendorStatus = try c.decodeIfPresent(VendorStatus.self, forKey: .vendorStatus)
            self.rttMs = try c.decodeIfPresent(Double.self, forKey: .rttMs)
            self.ttl = try c.decodeIfPresent(Int.self, forKey: .ttl)
            self.netbiosName = try c.decodeIfPresent(String.self, forKey: .netbiosName)
            self.workgroup = try c.decodeIfPresent(String.self, forKey: .workgroup)
            self.openPorts = try c.decodeIfPresent([Int].self, forKey: .openPorts) ?? []
            self.serviceTitle = try c.decodeIfPresent(String.self, forKey: .serviceTitle)
            self.model = try c.decodeIfPresent(String.self, forKey: .model)
            self.bonjourName = try c.decodeIfPresent(String.self, forKey: .bonjourName)
            self.services = try c.decodeIfPresent([String].self, forKey: .services) ?? []
            self.role = try c.decodeIfPresent(Host.Role.self, forKey: .role)
            self.status = try c.decodeIfPresent(Host.Status.self, forKey: .status) ?? .alive
        }
    }
}

public enum SnapshotIO {
    public static func encode(_ snapshot: ScanSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> ScanSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanSnapshot.self, from: data)
    }

    public static func defaultFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "SimpleScanner-\(formatter.string(from: now)).\(ScanSnapshot.fileExtension)"
    }
}
