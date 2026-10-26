import Foundation

public enum ExportService {
    public struct Row: Codable, Sendable {
        public let ip: String
        public let label: String?
        public let hostname: String?
        public let mac: String?
        public let vendor: String?
        public let rttMs: Double?
        public let ttl: Int?
        public let openPorts: [Int]
        public let netbiosName: String?
        public let workgroup: String?
        public let serviceTitle: String?
        public var vendorStatus: VendorStatus? = nil
        public var role: Host.Role? = nil
        public var deviceType: String? = nil
        public let status: Host.Status

        public init(ip: String, label: String?, hostname: String?, mac: String?, vendor: String?, rttMs: Double?, ttl: Int?,
                    openPorts: [Int], netbiosName: String?, workgroup: String?, serviceTitle: String?,
                    vendorStatus: VendorStatus? = nil, role: Host.Role? = nil, deviceType: String? = nil, status: Host.Status) {
            self.ip = ip; self.label = label; self.hostname = hostname; self.mac = mac; self.vendor = vendor
            self.rttMs = rttMs; self.ttl = ttl; self.openPorts = openPorts; self.netbiosName = netbiosName
            self.workgroup = workgroup; self.serviceTitle = serviceTitle; self.vendorStatus = vendorStatus
            self.role = role; self.deviceType = deviceType; self.status = status
        }
    }

    public static func rows(from hosts: [Host], label: (Host) -> String?) -> [Row] {
        hosts.map { h in
            Row(
                ip: h.ip,
                label: label(h),
                hostname: h.hostname ?? h.bonjourName,
                mac: h.mac,
                vendor: h.vendor,
                rttMs: h.rttMs,
                ttl: h.ttl,
                openPorts: h.openPorts,
                netbiosName: h.netbiosName,
                workgroup: h.workgroup,
                serviceTitle: h.serviceTitle ?? h.model,
                vendorStatus: h.vendorStatus,
                role: h.role,
                deviceType: DeviceClassifier.classify(h) == .unknown ? nil : DeviceClassifier.classify(h).rawValue,
                status: h.status
            )
        }
    }

    public static func csv(rows: [Row]) -> String {
        var out = "IP,Label,Hostname,MAC,Vendor,RTT (ms),TTL,Open Ports,NetBIOS Name,Workgroup,Service Title,Status\n"
        for r in rows {
            let rtt = r.rttMs.map { String(format: "%.1f", $0) } ?? ""
            let ttl = r.ttl.map(String.init) ?? ""
            let ports = r.openPorts.map(String.init).joined(separator: ";")
            let cells = [
                escape(r.ip), escape(r.label), escape(r.hostname), escape(r.mac), escape(r.vendor),
                rtt, ttl, escape(ports), escape(r.netbiosName), escape(r.workgroup), escape(r.serviceTitle),
                escape(statusLabel(r.status))
            ]
            out += cells.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func statusLabel(_ status: Host.Status) -> String {
        switch status {
        case .alive: return "alive"
        case .dead: return "dead"
        case .scanning: return "scanning"
        }
    }

    public static func json(rows: [Row]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(rows)
    }

    /// Flat `ip:port` lines, one per (host, open port) pair. Skips hosts with no open ports.
    public static func ipPortList(rows: [Row]) -> String {
        var lines: [String] = []
        for r in rows where !r.openPorts.isEmpty {
            for port in r.openPorts { lines.append("\(r.ip):\(port)") }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// Human-readable plain-text report.
    public static func textReport(rows: [Row], rangeInput: String, scannedTotal: Int, aliveCount: Int, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var out = L("Rapport SimpleScanner\n", "SimpleScanner Report\n")
        out += L("Généré le : \(formatter.string(from: now))\n", "Generated: \(formatter.string(from: now))\n")
        if !rangeInput.isEmpty { out += L("Plage : \(rangeInput)\n", "Range: \(rangeInput)\n") }
        out += L("Adresses sondées : \(scannedTotal)\n", "Addresses probed: \(scannedTotal)\n")
        out += L("Appareils trouvés : \(aliveCount)\n", "Devices found: \(aliveCount)\n")
        out += String(repeating: "-", count: 60) + "\n"

        let ipWidth = max(15, rows.map { $0.ip.count }.max() ?? 15)
        func displayName(_ r: Row) -> String {
            let base = r.label ?? r.hostname ?? r.netbiosName ?? "—"
            guard let role = r.role else { return base }
            return "\(base) (\(role.label.lowercased()))"
        }
        let hostWidth = max(20, rows.map { displayName($0).count }.max() ?? 20)
        let vendorWidth = max(20, rows.map { ($0.vendor ?? "").count }.max() ?? 20)
        let statusWidth = max(8, rows.map { statusLabel($0.status).count }.max() ?? 8)

        out += pad("IP", to: ipWidth) + "  " + pad(L("Nom", "Name"), to: hostWidth) + "  " + pad(L("Fabricant", "Vendor"), to: vendorWidth) + "  " + pad(L("État", "Status"), to: statusWidth) + "  " + L("Ports", "Ports") + "\n"
        out += String(repeating: "-", count: 60) + "\n"
        for r in rows {
            let ports = r.openPorts.map(String.init).joined(separator: ", ")
            let title = r.serviceTitle.map { " · \($0)" } ?? ""
            out += pad(r.ip, to: ipWidth) + "  "
                + pad(displayName(r), to: hostWidth) + "  "
                + pad(r.vendor ?? "—", to: vendorWidth) + "  "
                + pad(statusLabel(r.status), to: statusWidth) + "  "
                + (ports.isEmpty ? "—" : ports) + title + "\n"
        }
        return out
    }

    public static func defaultFileName(ext: String, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "SimpleScanner-\(formatter.string(from: now)).\(ext)"
    }

    private static func escape(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    private static func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
