import Foundation
import Network
import Observation
import SimpleScannerCore

/// Browses the usual Bonjour service families from launch and resolves each instance to an IPv4
/// address, keeping the TXT hints that name the hardware (`model=`, `md=`, `am=`).
@Observable
@MainActor
final class MDNSDiscovery {
    struct ServiceRecord: Hashable, Sendable {
        let displayType: String
        let serviceType: String
        /// The instance name, cleaned of MAC prefixes and hash suffixes.
        let name: String
        let ip: String
        var port: Int? = nil
        var model: String? = nil
    }

    /// Service families whose instance name is the device's own name, most trustworthy first.
    nonisolated static let identityTypes: [String] = [
        "_device-info._tcp", "_companion-link._tcp", "_smb._tcp", "_afpovertcp._tcp", "_sftp-ssh._tcp", "_ssh._tcp",
        "_rfb._tcp", "_workstation._tcp", "_airplay._tcp", "_hap._tcp", "_homekit._tcp", "_googlecast._tcp",
        "_printer._tcp", "_ipp._tcp", "_ipps._tcp", "_pdl-datastream._tcp", "_scanner._tcp", "_hue._tcp",
        "_sonos._tcp", "_raop._tcp", "_http._tcp", "_https._tcp", "_oscjson._tcp", "_osc._udp", "_ndi._tcp",
    ]

    /// `3AB608DB6D2A@Salon` → `Salon`, `Chromecast-0a1b…` → `Chromecast`, `name [aa:bb:…]` → `name`, `Salon (2)` → `Salon`.
    nonisolated static func cleanName(_ raw: String, type: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if let at = name.firstIndex(of: "@"), at > name.startIndex, at < name.index(before: name.endIndex) {
            let prefix = name[..<at]
            if type == "_raop._tcp" || type == "_sonos._tcp" || prefix.allSatisfy({ $0.isHexDigit || $0 == "-" || $0 == "_" }) {
                name = String(name[name.index(after: at)...])
            }
        }
        if name.hasSuffix("]"), let bracket = name.range(of: " [", options: .backwards) {
            name = String(name[..<bracket.lowerBound])
        }
        if let dash = name.lastIndex(of: "-") {
            let tail = name[name.index(after: dash)...]
            if tail.count >= 16, tail.allSatisfy(\.isHexDigit) { name = String(name[..<dash]) }
        }
        while let suffix = name.range(of: #" \(\d+\)$"#, options: .regularExpression) { name.removeSubrange(suffix) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Instance names ordered by how much they say about the device, duplicates removed.
    nonisolated static func names(from records: [ServiceRecord]) -> [String] {
        let ranked = records.sorted { a, b in
            let ia = identityTypes.firstIndex(of: a.serviceType) ?? identityTypes.count
            let ib = identityTypes.firstIndex(of: b.serviceType) ?? identityTypes.count
            return ia != ib ? ia < ib : a.name < b.name
        }
        var names: [String] = []
        for record in ranked where !record.name.isEmpty && !names.contains(record.name) && record.serviceType != "_device-info._tcp" {
            names.append(record.name)
        }
        return names
    }

    /// What Bonjour knows about one address.
    struct DeviceInfo: Equatable {
        var services: [String] = []
        var names: [String] = []
        var model: String?
    }

    static let serviceTypes: [(type: String, label: String)] = [
        ("_airplay._tcp", "AirPlay"),
        ("_raop._tcp", "AirPlay audio"),
        ("_googlecast._tcp", "Chromecast"),
        ("_companion-link._tcp", "Apple Companion"),
        ("_homekit._tcp", "HomeKit"),
        ("_hap._tcp", "HomeKit"),
        ("_smb._tcp", "SMB"),
        ("_afpovertcp._tcp", "AFP"),
        ("_nfs._tcp", "NFS"),
        ("_ssh._tcp", "SSH"),
        ("_sftp-ssh._tcp", "SFTP"),
        ("_rfb._tcp", "Partage d'écran"),
        ("_workstation._tcp", "Poste de travail"),
        ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS"),
        ("_ipp._tcp", "IPP"),
        ("_ipps._tcp", "IPP"),
        ("_printer._tcp", "Imprimante"),
        ("_pdl-datastream._tcp", "Impression"),
        ("_scanner._tcp", "Scanner"),
        ("_spotify-connect._tcp", "Spotify Connect"),
        ("_sonos._tcp", "Sonos"),
        ("_hue._tcp", "Philips Hue"),
        ("_osc._udp", "OSC"),
        ("_oscjson._tcp", "OSCQuery"),
        ("_ndi._tcp", "NDI"),
        ("_device-info._tcp", "Infos appareil"),
    ]

    private(set) var servicesByIP: [String: Set<ServiceRecord>] = [:]
    /// `_device-info._tcp` instances carry no address; they are matched to hosts by name.
    private(set) var deviceInfoModels: [String: String] = [:]
    private var browsers: [NWBrowser] = []
    private var connections: [String: NWConnection] = [:]
    private var inventory = BonjourInventory()
    private var monitor: NWPathMonitor?
    private var networkFingerprint: String?
    private var generation = UUID()
    private let resolveQueue = DispatchQueue(label: "simplescanner.mdns", attributes: .concurrent)
    var isRunning: Bool { !browsers.isEmpty }

    func start() {
        guard !isRunning else { return }
        let run = UUID(); generation = run
        for (type, label) in Self.serviceTypes {
            let parameters: NWParameters = type.hasSuffix("._udp") ? .udp : .tcp
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.handle(results: results, type: type, displayType: label, run: run)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                let addresses = NetworkInterface.scannableInterfaces().map { "\($0.name):\($0.ipv4)/\($0.netmaskBits)" }.sorted().joined(separator: ",")
                let fingerprint = "\(path.status):\(addresses)"
                if let previous = self.networkFingerprint, previous != fingerprint {
                    self.stop(); self.start()
                } else { self.networkFingerprint = fingerprint }
            }
        }
        monitor.start(queue: resolveQueue)
    }

    func stop() {
        generation = UUID()
        for browser in browsers { browser.cancel() }
        browsers.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        inventory = BonjourInventory()
        servicesByIP = [:]
        deviceInfoModels = [:]
        monitor?.cancel(); monitor = nil; networkFingerprint = nil
    }

    func services(for ip: String) -> [ServiceRecord] {
        Array(servicesByIP[ip] ?? []).sorted { ($0.displayType, $0.name) < ($1.displayType, $1.name) }
    }

    /// Service families, instance names and the best model hint for one address.
    func info(for host: Host) -> DeviceInfo {
        let records = services(for: host.ip)
        var info = DeviceInfo()
        info.services = Array(Set(records.map(\.displayType)).subtracting(["Infos appareil"])).sorted()
        let names = Self.names(from: records)
        info.names = names
        info.model = records.compactMap(\.model).first ?? deviceInfoModel(for: host, names: names)
        return info
    }

    /// Every service family currently visible on the network, with the number of devices.
    var serviceCatalog: [(type: String, count: Int)] {
        var counts: [String: Set<String>] = [:]
        for (ip, records) in servicesByIP {
            for record in records where record.displayType != "Infos appareil" { counts[record.displayType, default: []].insert(ip) }
        }
        return counts.map { (type: $0.key, count: $0.value.count) }.sorted { $0.type < $1.type }
    }

    private func deviceInfoModel(for host: Host, names: [String]) -> String? {
        let candidates = ([host.hostname?.split(separator: ".").first.map(String.init), host.netbiosName] + names).compactMap { $0 }
        for candidate in candidates {
            let key = Self.normalized(candidate)
            if let model = deviceInfoModels[key] { return model }
        }
        return nil
    }

    nonisolated static func normalized(_ name: String) -> String {
        name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
    }

    nonisolated static func modelHint(from txt: NWTXTRecord?) -> String? {
        guard let txt else { return nil }
        for key in ["model", "md", "am", "ty", "product"] {
            if case .string(let value)? = txt.getEntry(for: key), !value.isEmpty { return value }
        }
        return nil
    }

    private func handle(results: Set<NWBrowser.Result>, type: String, displayType: String, run: UUID) {
        var endpoints: [String: (endpoint: NWEndpoint, name: String, model: String?)] = [:]
        for result in results {
            guard case .service(let rawName, _, let domain, let interface) = result.endpoint else { continue }
            let id = "\(type)|\(domain)|\(rawName)|\(interface?.index ?? 0)"
            var model: String?
            var name = Self.cleanName(rawName, type: type)
            if case .bonjour(let txt) = result.metadata {
                model = Self.modelHint(from: txt)
                // Cast devices publish a hash as instance name and their friendly name in TXT.
                if type == "_googlecast._tcp", case .string(let friendly)? = txt.getEntry(for: "fn"), !friendly.isEmpty { name = friendly }
            }
            endpoints[id] = (result.endpoint, name, model)
        }
        if type == "_device-info._tcp" {
            // No listener behind these: keep the model keyed by the device name.
            var models: [String: String] = [:]
            for value in endpoints.values { if let model = value.model { models[Self.normalized(value.name)] = model } }
            deviceInfoModels = models
            return
        }
        let removed = inventory.reconcile(ids: Set(endpoints.keys), type: type)
        for id in removed { connections.removeValue(forKey: id)?.cancel() }
        rebuild()
        for (id, value) in endpoints where connections[id] == nil && inventory.records[id] == nil {
            guard let token = inventory.tokens[id] else { continue }
            let connection = NWConnection(to: value.endpoint, using: type.hasSuffix("._udp") ? .udp : .tcp)
            connections[id] = connection
            let model = value.model
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let connection else { return }
                switch state {
                case .ready:
                    var host: NWEndpoint.Host?
                    var port: Int?
                    if let path = connection.currentPath, case .hostPort(let remote, let remotePort) = path.remoteEndpoint { host = remote; port = Int(remotePort.rawValue) }
                    let ip = host.flatMap(Self.ipv4String)
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if let ip { self.inventory.accept(.init(displayType: displayType, serviceType: type, name: value.name, ip: ip, port: port, model: model), id: id, token: token) }
                        self.rebuild()
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                    }
                default: break
                }
            }
            connection.start(queue: resolveQueue)
            Task { @MainActor [weak self, weak connection] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let connection, self.generation == run, self.connections[id] === connection else { return }
                self.connections.removeValue(forKey: id); connection.cancel()
            }
        }
    }

    private func rebuild() {
        servicesByIP = Dictionary(grouping: inventory.records.values, by: \.ip).mapValues(Set.init)
    }

    nonisolated private static func ipv4String(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let addr):
            let bytes = addr.rawValue
            guard bytes.count == 4 else { return nil }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        default:
            return nil
        }
    }
}

/// Reconciles complete browser snapshots and rejects a late resolution after removal.
struct BonjourInventory {
    private(set) var tokens: [String: UUID] = [:]
    private(set) var records: [String: MDNSDiscovery.ServiceRecord] = [:]

    mutating func reconcile(ids: Set<String>, type: String) -> Set<String> {
        let previous = Set(tokens.keys.filter { $0.hasPrefix(type + "|") })
        let removed = previous.subtracting(ids)
        for id in removed { tokens.removeValue(forKey: id); records.removeValue(forKey: id) }
        for id in ids where tokens[id] == nil { tokens[id] = UUID() }
        return removed
    }

    mutating func accept(_ record: MDNSDiscovery.ServiceRecord, id: String, token: UUID) {
        guard tokens[id] == token else { return }
        records[id] = record
    }
}
