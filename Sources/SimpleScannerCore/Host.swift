import Foundation

/// One address of a scan, as discovered so far. Enrichment events are folded in with `merged(with:)`.
public struct Host: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Codable, Sendable {
        case scanning
        case alive
        case dead
    }

    /// How the address was found to be alive.
    public enum Discovery: String, Codable, Sendable {
        case icmp, arp, tcp
    }

    public let id: UUID
    public var ip: String
    public var hostname: String?
    public var mac: String?
    public var vendorStatus: VendorStatus?
    public var vendor: String?
    public var rttMs: Double?
    public var ttl: Int?
    public var netbiosName: String?
    public var workgroup: String?
    public var openPorts: [Int]
    public var serviceTitle: String?
    /// Hardware model advertised over Bonjour (`model=` / `md=` TXT keys), e.g. `MacBookPro18,1`.
    public var model: String?
    /// Instance name of a Bonjour service published by the device, e.g. `Salon` or `HP LaserJet`.
    public var bonjourName: String?
    /// Bonjour service families seen on the device, as display names (`AirPlay`, `SMB`, …).
    public var services: [String]
    public var discoveredBy: Discovery?
    public var status: Status

    public init(
        id: UUID = UUID(),
        ip: String,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        vendorStatus: VendorStatus? = nil,
        rttMs: Double? = nil,
        ttl: Int? = nil,
        netbiosName: String? = nil,
        workgroup: String? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil,
        model: String? = nil,
        bonjourName: String? = nil,
        services: [String] = [],
        discoveredBy: Discovery? = nil,
        status: Status = .scanning
    ) {
        self.id = id
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
        self.discoveredBy = discoveredBy
        self.status = status
    }

    public var ipNumeric: UInt32 { IPv4.uint32(from: ip) ?? 0 }

    /// Best human name: DNS label, NetBIOS name, Bonjour name, in that order.
    public var displayName: String? {
        if let hostname, !hostname.isEmpty {
            let label = hostname.split(separator: ".").first.map(String.init) ?? hostname
            return label
        }
        if let netbiosName, !netbiosName.isEmpty { return netbiosName }
        if let bonjourName, !bonjourName.isEmpty { return bonjourName }
        return nil
    }

    /// Merges a newer partial-result `update` onto `self`, keeping any field `update` left empty.
    /// Shared by the scan loop and the headless `--scan` mode so they cannot diverge.
    public func merged(with update: Host) -> Host {
        var merged = self
        if let v = update.hostname { merged.hostname = v }
        if let v = update.mac { merged.mac = v }
        if let status = update.vendorStatus {
            merged.mac = update.mac
            merged.vendor = update.vendor
            merged.vendorStatus = status
        } else if let v = update.vendor { merged.vendor = v }
        if let v = update.rttMs { merged.rttMs = v }
        if let v = update.ttl { merged.ttl = v }
        if let v = update.netbiosName { merged.netbiosName = v }
        if let v = update.workgroup { merged.workgroup = v }
        if let v = update.serviceTitle { merged.serviceTitle = v }
        if let v = update.model { merged.model = v }
        if let v = update.bonjourName { merged.bonjourName = v }
        if !update.services.isEmpty { merged.services = update.services }
        if let v = update.discoveredBy { merged.discoveredBy = v }
        merged.openPorts = update.openPorts.isEmpty ? merged.openPorts : update.openPorts
        merged.status = update.status
        return merged
    }
}
