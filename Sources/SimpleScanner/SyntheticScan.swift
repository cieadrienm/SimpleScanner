import Foundation
import SimpleScannerCore

/// A believable small network for `--snapshot`, the self-test and the demo: no packet leaves the Mac.
enum SyntheticScan {
    static let range = "192.168.1.0/24"

    static func hosts() -> [Host] {
        [
            Host(ip: "192.168.1.1", hostname: "freebox.local", mac: "68:a3:78:12:9b:01", vendor: "Freebox SA", vendorStatus: .matched, rttMs: 1.4, ttl: 64, openPorts: [80, 443], serviceTitle: "Freebox OS", services: ["HTTP"], discoveredBy: .icmp, role: .gateway, status: .alive),
            Host(ip: "192.168.1.12", hostname: "studio.local", mac: "f0:18:98:4c:2a:7d", vendor: "Apple, Inc.", vendorStatus: .matched, rttMs: 0.6, ttl: 64, openPorts: [22, 445, 5900], model: "MacStudio13,1", bonjourName: "Studio", services: ["AirPlay", "Partage d'écran", "SMB", "SSH"], discoveredBy: .icmp, role: .thisMac, status: .alive),
            Host(ip: "192.168.1.23", hostname: "iphone-adrien.local", mac: "2a:91:f0:5e:66:c3", vendorStatus: .localAddress, rttMs: 38.2, ttl: 64, model: "iPhone16,1", bonjourName: "iPhone", services: ["Apple Companion"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.30", hostname: "salon.local", mac: "d0:03:4b:71:0e:2f", vendor: "Apple, Inc.", vendorStatus: .matched, rttMs: 4.1, ttl: 64, openPorts: [7000], model: "AppleTV14,1", bonjourName: "Salon", services: ["AirPlay", "AirPlay audio"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.40", mac: "9c:8e:99:3a:11:52", vendor: "Hewlett Packard", vendorStatus: .matched, openPorts: [80, 631, 9100], serviceTitle: "HP LaserJet Pro M404", bonjourName: "HP LaserJet", services: ["HTTP", "IPP", "Impression"], discoveredBy: .arp, status: .alive),
            Host(ip: "192.168.1.50", hostname: "nas.local", mac: "00:11:32:9f:4e:d8", vendor: "Synology Incorporated", vendorStatus: .matched, rttMs: 0.9, ttl: 64, openPorts: [22, 445, 5000, 5001], serviceTitle: "DiskStation", services: ["AFP", "SMB", "HTTP"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.61", mac: "dc:a6:32:7b:90:14", vendor: "Raspberry Pi Trading Ltd", vendorStatus: .matched, rttMs: 2.3, ttl: 64, openPorts: [22], bonjourName: "regie", services: ["SSH", "OSC"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.77", hostname: "homepod-cuisine.local", mac: "7c:d1:c3:a8:50:9e", vendor: "Apple, Inc.", vendorStatus: .matched, rttMs: 12.7, ttl: 64, model: "AudioAccessory5,1", bonjourName: "Cuisine", services: ["AirPlay", "HomeKit"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.102", mac: "d4:be:d9:aa:bb:cc", vendor: "Dell Inc.", vendorStatus: .matched, rttMs: 1.1, ttl: 128, netbiosName: "PC-REGIE", workgroup: "WORKGROUP", openPorts: [135, 139, 445, 3389], discoveredBy: .tcp, status: .alive),
            Host(ip: "192.168.1.120", hostname: "shelly-plug.local", mac: "b8:27:eb:44:55:66", vendor: "Raspberry Pi Foundation", vendorStatus: .matched, rttMs: 3.0, ttl: 64, services: ["HomeKit"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.130", mac: "fc:ec:da:10:20:30", vendor: "Ubiquiti Inc", vendorStatus: .matched, rttMs: 0.8, ttl: 64, openPorts: [22, 80, 443], bonjourName: "U6-Lite", services: ["SSH"], discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.140", hostname: "nintendoswitch.local", mac: "98:b6:e9:aa:bb:cc", vendor: "Nintendo Co.,Ltd", vendorStatus: .matched, rttMs: 9.5, ttl: 64, discoveredBy: .icmp, status: .alive),
            Host(ip: "192.168.1.200", status: .dead),
            Host(ip: "192.168.1.201", status: .dead),
        ]
    }

    static var labels: [String: String] {
        [
            "f0:18:98:4c:2a:7d": L("Mac Studio régie #scène", "Booth Mac Studio #stage"),
            "dc:a6:32:7b:90:14": L("Raspberry OSC #scène", "OSC Raspberry #stage"),
            "9c:8e:99:3a:11:52": L("Imprimante bureau", "Office printer"),
        ]
    }

    static func snapshot(createdAt: Date = Date(timeIntervalSince1970: 1_792_000_000)) -> ScanSnapshot {
        ScanSnapshot(createdAt: createdAt, rangeInput: range, hosts: hosts().map(ScanSnapshot.HostRecord.init), labels: labels)
    }

    /// An older snapshot of the same network: one device gone, one new, one with different ports.
    static func baseline() -> ScanSnapshot {
        var records = hosts().filter { $0.status == .alive && $0.ip != "192.168.1.61" }.map(ScanSnapshot.HostRecord.init)
        records.append(ScanSnapshot.HostRecord(ip: "192.168.1.88", hostname: "ipad-tim.local", mac: "6e:21:ab:4d:00:17", vendor: nil, vendorStatus: .localAddress, rttMs: 20, ttl: 64, openPorts: [], serviceTitle: nil))
        records = records.map { r in
            guard r.ip == "192.168.1.50" else { return r }
            return ScanSnapshot.HostRecord(ip: r.ip, hostname: r.hostname, mac: r.mac, vendor: r.vendor, vendorStatus: r.vendorStatus, rttMs: r.rttMs, ttl: r.ttl, netbiosName: r.netbiosName, workgroup: r.workgroup, openPorts: [22, 445], serviceTitle: r.serviceTitle)
        }
        return ScanSnapshot(createdAt: Date(timeIntervalSince1970: 1_791_900_000), rangeInput: range, hosts: records, labels: labels)
    }

    @MainActor
    static func load(into model: AppModel, withComparison: Bool = true) {
        model.scan.applySnapshot(snapshot(), from: nil)
        if withComparison { model.scan.loadComparisonBaseline(baseline()) }
        if let studio = model.scan.hosts.first(where: { $0.ip == "192.168.1.12" }) {
            model.scan.selection = [studio.id]
        }
    }
}
