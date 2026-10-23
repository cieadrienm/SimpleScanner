import Foundation

public enum DeviceType: String, Hashable, CaseIterable, Sendable {
    case router
    case printer
    case tv
    case mac
    case phone
    case speaker
    case server
    case nas
    case iot
    case windows
    case unknown

    public var sfSymbol: String {
        switch self {
        case .router: "wifi.router"
        case .printer: "printer"
        case .tv: "tv"
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .speaker: "hifispeaker"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .iot: "homekit"
        case .windows: "pc"
        case .unknown: "questionmark.circle"
        }
    }

    public var label: String {
        switch self {
        case .router: "Routeur"
        case .printer: "Imprimante"
        case .tv: "TV"
        case .mac: "Mac"
        case .phone: "Téléphone"
        case .speaker: "Enceinte"
        case .server: "Serveur"
        case .nas: "NAS"
        case .iot: "Objet connecté"
        case .windows: "Windows"
        case .unknown: "Inconnu"
        }
    }
}

public struct DeviceClassification: Sendable {
    public let type: DeviceType
    public let evidence: String
}

/// Estimates a device family from names, vendor, ports, Bonjour model and services.
/// One family must stand alone; conflicting hints leave the type unknown.
public enum DeviceClassifier {
    public static func classify(_ host: Host) -> DeviceType { assessment(host).type }

    public static func assessment(_ host: Host) -> DeviceClassification {
        // A DNS search suffix belongs to the network, not the device.
        let name = (host.hostname ?? host.netbiosName ?? "").lowercased().split(separator: ".").first.map(String.init) ?? ""
        let vendor = (host.vendor ?? "").lowercased()
        let title = (host.serviceTitle ?? "").lowercased()
        let model = (host.model ?? "").lowercased()
        let services = Set(host.services)
        let ports = Set(host.openPorts)
        var evidence: [DeviceType: [String]] = [:]
        func add(_ type: DeviceType, _ reason: String) { evidence[type, default: []].append(reason) }

        if !model.isEmpty {
            if model.hasPrefix("iphone") || model.hasPrefix("ipad") || model.hasPrefix("ipod") || model.hasPrefix("watch") { add(.phone, "Modèle Bonjour \(host.model ?? "")") }
            else if model.hasPrefix("macbook") || model.hasPrefix("imac") || model.hasPrefix("macmini") || model.hasPrefix("macpro") || model.hasPrefix("macstudio") || model.hasPrefix("mac1") { add(.mac, "Modèle Bonjour \(host.model ?? "")") }
            else if model.hasPrefix("appletv") || model.contains("chromecast") || model.contains("googletv") { add(.tv, "Modèle Bonjour \(host.model ?? "")") }
            else if model.hasPrefix("audioaccessory") || model.contains("homepod") || model.contains("sonos") { add(.speaker, "Modèle Bonjour \(host.model ?? "")") }
            else if model.hasPrefix("airport") || model.contains("timecapsule") { add(.router, "Modèle Bonjour \(host.model ?? "")") }
        }
        if name.contains("iphone") || name.contains("ipad") || name.contains("android") || name.contains("pixel") || name.contains("galaxy") { add(.phone, "Le nom désigne un téléphone ou une tablette") }
        if name.contains("macbook") || name.contains("imac") || name == "mac" || name.hasSuffix("-mbp") || name.hasPrefix("mac-") || name.hasSuffix("-mac") || name.contains("mac-mini") || name.contains("macmini") { add(.mac, "Le nom désigne un Mac") }
        if name.contains("printer") || name.contains("imprimante") || title.contains("laserjet") || title.contains("officejet") { add(.printer, "Nom ou titre de service d'imprimante") }
        if ports.contains(9100) || ports.contains(515) { add(.printer, "Port d'impression ouvert") }
        if ports.contains(631) && (vendor.contains("brother") || vendor.contains("canon") || vendor.contains("epson") || name.contains("print")) { add(.printer, "IPP avec une identité d'imprimante") }
        if services.contains("IPP") || services.contains("Imprimante") { add(.printer, "Service d'impression Bonjour") }
        if name == "tv" || name.hasSuffix("-tv") || name.hasPrefix("tv-") || name.contains("appletv") || name.contains("apple-tv") || title.contains("smart tv") { add(.tv, "Nom ou titre de téléviseur") }
        if services.contains("Chromecast") { add(.tv, "Service Chromecast") }
        if name.hasPrefix("homepod") || name.contains("sonos") { add(.speaker, "Le nom désigne une enceinte") }
        if ["router", "gateway", "hgw", "box"].contains(name) || name.hasSuffix("-router") || name.hasSuffix("-gateway")
            || ["freebox", "livebox", "bbox", "sfrbox", "fritz", "openwrt", "unifi", "ubnt", "routeur"].contains(where: { name.hasPrefix($0) }) { add(.router, "Nom de routeur ou de box") }
        if name == "nas" || name.hasSuffix("-nas") || name.hasPrefix("nas-") || name.hasPrefix("diskstation") || ((vendor.contains("synology") || vendor.contains("qnap")) && !ports.intersection([445, 5000, 5001, 2049]).isEmpty) { add(.nas, "Identité NAS et service de stockage") }
        if ports.contains(445) && (ports.contains(135) || ports.contains(139)) { add(.windows, "Services SMB et RPC/NetBIOS Windows") }
        if host.workgroup != nil, host.netbiosName != nil, ports.isEmpty, evidence.isEmpty { add(.windows, "Nom NetBIOS et groupe de travail") }
        if (vendor.contains("espressif") || vendor.contains("tuya") || vendor.contains("sonoff") || vendor.contains("shelly") || vendor.contains("raspberry")) && (!ports.isEmpty || !services.isEmpty) { add(.iot, "Fabricant de cartes embarquées avec un service joignable") }
        if services.contains("HomeKit"), evidence.isEmpty { add(.iot, "Accessoire HomeKit") }

        guard evidence.count == 1, let match = evidence.first else {
            return .init(type: .unknown, evidence: evidence.isEmpty ? "Pas assez d'indices pour estimer le type d'appareil." : "Indices contradictoires ; type laissé inconnu.")
        }
        return .init(type: match.key, evidence: match.value.joined(separator: " ; ") + ". Il s'agit d'une estimation.")
    }
}
