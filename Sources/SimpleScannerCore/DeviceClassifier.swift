import Foundation

public enum DeviceType: String, Hashable, CaseIterable, Sendable {
    case router, networkGear, printer, tv, mac, phone, watch, speaker, camera, console, server, nas, iot, windows, linux, computer, unknown

    public var sfSymbol: String {
        switch self {
        case .router: "wifi.router"
        case .networkGear: "point.3.connected.trianglepath.dotted"
        case .printer: "printer"
        case .tv: "tv"
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .watch: "applewatch"
        case .speaker: "hifispeaker"
        case .camera: "video"
        case .console: "gamecontroller"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .iot: "homekit"
        case .windows: "pc"
        case .linux: "terminal"
        case .computer: "desktopcomputer"
        case .unknown: "questionmark.circle"
        }
    }

    public var label: String {
        switch self {
        case .router: "Routeur / box"
        case .networkGear: "Switch / point d'accès"
        case .printer: "Imprimante"
        case .tv: "TV / boîtier vidéo"
        case .mac: "Mac"
        case .phone: "Téléphone / tablette"
        case .watch: "Montre"
        case .speaker: "Enceinte"
        case .camera: "Caméra"
        case .console: "Console de jeu"
        case .server: "Serveur"
        case .nas: "NAS"
        case .iot: "Objet connecté"
        case .windows: "PC Windows"
        case .linux: "Linux / Raspberry"
        case .computer: "Ordinateur"
        case .unknown: "Inconnu"
        }
    }

    /// Specific families that may share the generic `computer` family.
    var isComputer: Bool { self == .mac || self == .windows || self == .linux || self == .computer }
}

public struct DeviceClassification: Sendable {
    public enum Confidence: Sendable { case strong, probable }

    public let type: DeviceType
    public let confidence: Confidence
    /// Why, most decisive first.
    public let reasons: [String]
    /// A symbol refined from the model (iPad, desktop Mac…).
    public let symbol: String

    public var isCertain: Bool { confidence == .strong }
    public var evidence: String {
        guard type != .unknown else { return reasons.first ?? "Pas assez d'indices pour estimer le type d'appareil." }
        return reasons.joined(separator: " ; ") + (confidence == .strong ? "." : ". Estimation à confirmer.")
    }
}

/// Estimates a device family by adding up hints from names, vendor, ports, TTL, Bonjour and known roles.
/// The leading family must score at least twice the runner-up; close calls stay unknown.
public enum DeviceClassifier {
    public static func classify(_ host: Host) -> DeviceType { assessment(host).type }

    public static func assessment(_ host: Host) -> DeviceClassification {
        var scores: [DeviceType: Int] = [:]
        var reasons: [DeviceType: [String]] = [:]
        func hint(_ type: DeviceType, _ weight: Int, _ reason: String) {
            scores[type, default: 0] += weight
            reasons[type, default: []].append(reason)
        }

        // A DNS search suffix belongs to the network, not the device.
        let name = (host.hostname ?? host.netbiosName ?? host.bonjourName ?? "").lowercased().split(separator: ".").first.map(String.init) ?? ""
        let vendor = (host.vendor ?? "").lowercased()
        let title = (host.serviceTitle ?? "").lowercased()
        let model = (host.model ?? "").lowercased()
        let services = Set(host.services)
        let ports = Set(host.openPorts)
        func nameHas(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }
        func namePrefix(_ needles: String...) -> Bool { needles.contains { name.hasPrefix($0) } }
        func nameSuffix(_ needles: String...) -> Bool { needles.contains { name.hasSuffix($0) } }
        func vendorHas(_ needles: String...) -> Bool { needles.contains { vendor.contains($0) } }

        // Roles are facts.
        switch host.role {
        case .thisMac: hint(.mac, 6, "C'est ce Mac")
        case .gateway: hint(.router, 4, "Passerelle par défaut du réseau")
        case nil: break
        }

        // Bonjour or sysctl model.
        if !model.isEmpty {
            let shown = "Modèle \(host.model ?? "")"
            if model.hasPrefix("iphone") || model.hasPrefix("ipod") || model.hasPrefix("ipad") { hint(.phone, 3, shown) }
            else if model.hasPrefix("watch") { hint(.watch, 3, shown) }
            else if model.hasPrefix("macbook") || model.hasPrefix("imac") || model.hasPrefix("macmini") || model.hasPrefix("macpro") || model.hasPrefix("macstudio") || model.hasPrefix("mac1") || model.hasPrefix("mac2") { hint(.mac, 3, shown) }
            else if model.hasPrefix("appletv") || model.contains("chromecast") || model.contains("googletv") || model.contains("shield") || model.contains("roku") || model.contains("firetv") { hint(.tv, 3, shown) }
            else if model.hasPrefix("audioaccessory") || model.contains("homepod") || model.contains("sonos") || model.contains("nest audio") || model.contains("echo") { hint(.speaker, 3, shown) }
            else if model.hasPrefix("airport") || model.contains("timecapsule") { hint(.router, 3, shown) }
            else if model.contains("switch") || model.contains("uap") || model.hasPrefix("u6") || model.contains("access point") { hint(.networkGear, 3, shown) }
            else if model.contains("raspberry") { hint(.linux, 3, shown) }
            else if model.contains("printer") || model.contains("laserjet") || model.contains("officejet") || model.contains("pixma") || model.contains("ecotank") || model.contains("mfc") { hint(.printer, 3, shown) }
            else if model.contains("camera") || model.contains("cam ") { hint(.camera, 3, shown) }
            else if model.contains("tv") { hint(.tv, 2, shown) }
        }

        // Names: DNS, NetBIOS or Bonjour.
        if !name.isEmpty {
            let why = "Le nom « \(name) »"
            if nameHas("iphone", "ipod", "ipad", "android", "galaxy", "pixel", "oneplus", "xiaomi", "redmi", "oppo", "fairphone") || nameSuffix("-phone") { hint(.phone, 2, "\(why) désigne un téléphone ou une tablette") }
            if nameHas("macbook", "imac", "mac-mini", "macmini", "mac-studio", "macstudio", "mac-pro", "macpro", "-mbp", "-mba", "mbp-", "mba-") || name == "mac" || namePrefix("mac-") || nameSuffix("-mac") { hint(.mac, 2, "\(why) désigne un Mac") }
            if namePrefix("desktop-", "laptop-", "win-", "pc-") || nameSuffix("-pc", "-win") || nameHas("windows") { hint(.windows, 2, "\(why) suit la convention Windows") }
            if nameHas("raspberrypi", "raspberry", "rpi", "ubuntu", "debian", "fedora", "archlinux", "nixos", "-linux") { hint(.linux, 2, "\(why) désigne une machine Linux") }
            if nameHas("printer", "imprimante", "laserjet", "officejet", "pixma", "ecotank") || namePrefix("epson", "brother", "canon", "hp-") || title.contains("laserjet") || title.contains("officejet") { hint(.printer, 2, "\(why) ou le titre de service désigne une imprimante") }
            if name == "tv" || nameSuffix("-tv", "tv") || namePrefix("tv-") || nameHas("appletv", "apple-tv", "bravia", "chromecast", "firetv", "shield", "roku", "freebox-player") || title.contains("smart tv") { hint(.tv, 2, "\(why) désigne un téléviseur ou un boîtier vidéo") }
            if nameHas("homepod", "sonos", "bose", "speaker", "enceinte") || namePrefix("echo-", "nest-") { hint(.speaker, 2, "\(why) désigne une enceinte") }
            if ["router", "gateway", "hgw", "box", "routeur", "openwrt"].contains(name) || nameSuffix("-router", "-gateway", "-gw") || namePrefix("freebox", "livebox", "bbox", "sfrbox", "fritz", "udm", "usg", "gw-", "router", "routeur") { hint(.router, 2, "\(why) désigne un routeur ou une box") }
            if nameHas("switch", "accesspoint", "access-point", "unifi-ap", "-uap", "uap-", "u6-", "u7-") || namePrefix("sw-", "ap-") || nameSuffix("-sw", "-ap") { hint(nameHas("nintendo") ? .console : .networkGear, 2, "\(why) désigne un switch ou un point d'accès") }
            if name == "nas" || nameSuffix("-nas") || namePrefix("nas-", "diskstation", "synology", "qnap", "truenas", "unraid") { hint(.nas, 2, "\(why) désigne un NAS") }
            if nameHas("camera", "ipcam", "doorbell", "-cam", "cam-", "webcam") || namePrefix("cam") || namePrefix("ring-", "arlo", "reolink") { hint(.camera, 2, "\(why) désigne une caméra") }
            if nameHas("playstation", "ps4", "ps5", "xbox", "nintendo") { hint(.console, 2, "\(why) désigne une console de jeu") }
            if nameHas("server", "serveur", "proxmox", "esxi", "vcenter") || namePrefix("srv-", "srv") || nameSuffix("-srv") { hint(.server, 2, "\(why) désigne un serveur") }
            if nameHas("shelly", "tasmota", "sonoff", "tuya", "thermostat", "hue-", "bridge", "homekit", "aqara") || namePrefix("esp-", "esp_", "esp32", "esp8266") { hint(.iot, 2, "\(why) désigne un objet connecté") }
            if nameHas("watch") { hint(.watch, 2, "\(why) désigne une montre") }
        }

        // Vendor (IEEE registry). Ambiguous makers (Apple, Samsung, HP, Huawei, ASUS…) say nothing alone.
        if !vendor.isEmpty {
            let why = "Fabricant \(host.vendor ?? "")"
            if vendorHas("freebox", "sagemcom", "technicolor", "arcadyan", "avm ", "avm gmbh", "askey", "sercomm", "hitron", "zte", "orange", "bouygues", "sfr", "iliad") { hint(.router, 2, "\(why), fabricant de box") }
            if vendorHas("ubiquiti", "netgear", "tp-link", "d-link", "cisco", "meraki", "juniper", "mikrotik", "aruba", "ruckus", "zyxel", "linksys", "belkin", "engenius", "edimax", "cambium", "draytek", "fortinet") { hint(.networkGear, 2, "\(why), équipement réseau") }
            if vendorHas("synology", "qnap", "western digital", "buffalo", "asustor", "terramaster") {
                hint(.nas, ports.isDisjoint(with: [445, 548, 2049, 5000, 5001, 6690]) ? 1 : 3, "\(why), fabricant de NAS\(ports.isDisjoint(with: [445, 548, 2049, 5000, 5001, 6690]) ? "" : " avec un service de stockage ouvert")")
            }
            if vendorHas("sonos", "bose", "denon", "marantz", "yamaha", "devialet", "bang & olufsen", "harman", "jbl", "teufel", "bluesound", "naim") { hint(.speaker, 2, "\(why), fabricant d'enceintes") }
            if vendorHas("hikvision", "dahua", "axis communications", "reolink", "arlo", "amcrest", "foscam", "wyze", "eufy", "annke") { hint(.camera, 2, "\(why), fabricant de caméras") }
            if vendorHas("nintendo", "sony interactive") { hint(.console, 3, "\(why), fabricant de consoles") }
            if vendorHas("espressif", "tuya", "sonoff", "itead", "shelly", "allterco", "philips lighting", "signify", "lifx", "aqara", "lumi united", "somfy", "legrand", "delta dore", "tado", "ecobee", "nest labs", "ring llc", "netatmo") { hint(.iot, 2, "\(why), fabricant d'objets connectés") }
            if vendorHas("brother", "canon", "epson", "lexmark", "kyocera", "ricoh", "konica", "oki ", "xerox", "zebra") { hint(.printer, 2, "\(why), fabricant d'imprimantes") }
            if vendorHas("raspberry", "beagle", "hardkernel", "pine64") { hint(.linux, 2, "\(why), carte Linux") }
            if vendorHas("dell", "lenovo", "acer", "micro-star", "gigabyte", "intel corporate", "fujitsu", "toshiba") { hint(.computer, 1, "\(why), fabricant d'ordinateurs") }
            if vendorHas("oneplus", "oppo", "vivo", "motorola", "fairphone") { hint(.phone, 1, "\(why), fabricant de téléphones") }
            if vendorHas("vestel", "lg electronics", "tcl", "hisense", "vizio", "roku", "tp vision") { hint(.tv, 2, "\(why), fabricant de téléviseurs") }
            if vendorHas("samsung") { hint(.phone, 1, "\(why)"); hint(.tv, 1, "\(why)") }
        }

        // Bonjour service families.
        if services.contains("IPP") || services.contains("Imprimante") || services.contains("Impression") || services.contains("Scanner") { hint(.printer, 3, "Service d'impression Bonjour") }
        if services.contains("Chromecast") { hint(.tv, 2, "Service Chromecast") }
        if services.contains("AirPlay") { hint(.tv, 1, "Service AirPlay") }
        if services.contains("AirPlay audio"), !services.contains("AirPlay") { hint(.speaker, 2, "Récepteur AirPlay audio seul") }
        if services.contains("HomeKit") { hint(.iot, 2, "Accessoire HomeKit") }
        if services.contains("Sonos") { hint(.speaker, 3, "Service Sonos") }
        if services.contains("Philips Hue") { hint(.iot, 3, "Pont Philips Hue") }
        if services.contains("Spotify Connect") { hint(.speaker, 1, "Spotify Connect") }
        if services.contains("Poste de travail") { hint(.linux, 2, "Poste de travail annoncé par Avahi") }
        if services.contains("NDI") || services.contains("OSC") || services.contains("OSCQuery") { hint(.computer, 1, "Logiciel de spectacle (NDI / OSC)") }
        if services.contains("SSH") || services.contains("SFTP") { hint(.computer, 1, "Service SSH annoncé") }

        // Ports.
        if ports.contains(62078) { hint(.phone, 3, "Port 62078 (synchronisation iOS)") }
        if ports.contains(445) && (ports.contains(135) || ports.contains(139)) { hint(.windows, 3, "Services SMB et RPC/NetBIOS Windows") }
        if ports.contains(3389) { hint(.windows, 2, "Bureau à distance (3389)") }
        if ports.contains(5985) { hint(.windows, 2, "WinRM (5985)") }
        if ports.contains(9100) || ports.contains(515) { hint(.printer, 3, "Port d'impression ouvert") }
        if ports.contains(631) && (vendorHas("brother", "canon", "epson", "hewlett", "hp inc") || nameHas("print")) { hint(.printer, 2, "IPP avec une identité d'imprimante") }
        if ports.contains(548) { hint(.mac, 1, "Partage de fichiers AFP (548)") }
        if ports.contains(5900) && ports.contains(548) { hint(.mac, 1, "Partage d'écran et AFP") }
        if ports.contains(22), !ports.contains(445) { hint(.computer, 1, "SSH ouvert") }
        if !ports.isDisjoint(with: [32400, 8006, 10000, 9090, 3306, 5432, 6379, 27017, 9200, 6443, 2375]) { hint(.server, 2, "Service de serveur ouvert (\(PortScanner.formatList(ports.intersection([32400, 8006, 10000, 9090, 3306, 5432, 6379, 27017, 9200, 6443, 2375]).sorted())))") }
        if ports.contains(554) || ports.contains(8554) { hint(.camera, 2, "Flux RTSP (554)") }
        if ports.contains(1883) || ports.contains(8883) { hint(.iot, 2, "MQTT ouvert") }
        if ports.contains(161) && (ports.contains(80) || ports.contains(443)) { hint(.networkGear, 1, "SNMP avec une interface web") }
        if ports.contains(8009) { hint(.tv, 2, "Google Cast (8009)") }
        if ports.contains(7000), !services.contains("AirPlay") { hint(.tv, 1, "AirPlay (7000)") }
        if ports.contains(3074) || !ports.isDisjoint(with: [9295, 9296, 9297]) { hint(.console, 2, "Port de jeu en ligne") }
        if ports.contains(5555) { hint(.phone, 1, "Débogage Android (5555)") }

        // NetBIOS and TTL.
        if host.netbiosName != nil, host.workgroup != nil {
            hint(.windows, scores[.nas, default: 0] > 0 ? 1 : 2, "Nom NetBIOS et groupe de travail")
        }
        if let ttl = host.ttl {
            switch ttl {
            case 250...255: hint(.networkGear, 1, "TTL \(ttl) typique des équipements réseau"); hint(.router, 1, "TTL \(ttl) typique des équipements réseau")
            case 120...128: hint(.windows, 1, "TTL \(ttl) typique de Windows")
            default: break
            }
        }

        return decide(scores: scores, reasons: reasons, host: host, model: model, name: name)
    }

    private static func decide(scores: [DeviceType: Int], reasons: [DeviceType: [String]], host: Host, model: String, name: String) -> DeviceClassification {
        let ranked = scores.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
        guard let top = ranked.first else {
            return DeviceClassification(type: .unknown, confidence: .probable, reasons: ["Pas assez d'indices pour estimer le type d'appareil."], symbol: DeviceType.unknown.sfSymbol)
        }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        var winner = top.key
        var reasonList = reasons[winner] ?? []
        if top.value < 2 * runnerUp {
            // Close call. Computers of different stripes still make a computer.
            let contenders = ranked.filter { $0.value >= runnerUp }.map(\.key)
            guard contenders.allSatisfy(\.isComputer) else {
                return DeviceClassification(type: .unknown, confidence: .probable, reasons: ["Indices contradictoires (\(contenders.map(\.label).joined(separator: " / "))) ; type laissé inconnu."], symbol: DeviceType.unknown.sfSymbol)
            }
            let specific = contenders.filter { $0 != .computer }
            winner = specific.count == 1 ? specific[0] : .computer
            reasonList = contenders.flatMap { reasons[$0] ?? [] }
        }
        let confidence: DeviceClassification.Confidence = (top.value >= 3 && top.value >= runnerUp + 2) ? .strong : .probable
        return DeviceClassification(type: winner, confidence: confidence, reasons: reasonList, symbol: symbol(for: winner, model: model, name: name))
    }

    private static func symbol(for type: DeviceType, model: String, name: String) -> String {
        switch type {
        case .phone where model.hasPrefix("ipad") || name.contains("ipad"): return "ipad"
        case .mac where model.hasPrefix("imac") || model.hasPrefix("macmini") || model.hasPrefix("macstudio") || model.hasPrefix("macpro") || name.contains("imac") || name.contains("mini") || name.contains("studio"): return "desktopcomputer"
        default: return type.sfSymbol
        }
    }
}
