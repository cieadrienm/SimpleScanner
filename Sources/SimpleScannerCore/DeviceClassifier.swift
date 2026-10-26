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
        case .router: L("Routeur / box", "Router / gateway")
        case .networkGear: L("Switch / point d'accès", "Switch / access point")
        case .printer: L("Imprimante", "Printer")
        case .tv: L("TV / boîtier vidéo", "TV / media box")
        case .mac: "Mac"
        case .phone: L("Téléphone / tablette", "Phone / tablet")
        case .watch: L("Montre", "Watch")
        case .speaker: L("Enceinte", "Speaker")
        case .camera: L("Caméra", "Camera")
        case .console: L("Console de jeu", "Game console")
        case .server: L("Serveur", "Server")
        case .nas: "NAS"
        case .iot: L("Objet connecté", "IoT device")
        case .windows: L("PC Windows", "Windows PC")
        case .linux: "Linux / Raspberry"
        case .computer: L("Ordinateur", "Computer")
        case .unknown: L("Inconnu", "Unknown")
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
        guard type != .unknown else { return reasons.first ?? L("Pas assez d'indices pour estimer le type d'appareil.", "Not enough clues to estimate the device type.") }
        return reasons.joined(separator: " ; ") + (confidence == .strong ? "." : L(". Estimation à confirmer.", ". Probable estimate."))
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
        case .thisMac: hint(.mac, 6, L("C'est ce Mac", "This is this Mac"))
        case .gateway: hint(.router, 4, L("Passerelle par défaut du réseau", "Default network gateway"))
        case nil: break
        }

        // Bonjour or sysctl model.
        if !model.isEmpty {
            let shown = L("Modèle \(host.model ?? "")", "Model \(host.model ?? "")")
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
            let why = L("Le nom « \(name) »", "Name “\(name)”")
            if nameHas("iphone", "ipod", "ipad", "android", "galaxy", "pixel", "oneplus", "xiaomi", "redmi", "oppo", "fairphone") || nameSuffix("-phone") { hint(.phone, 2, L("\(why) désigne un téléphone ou une tablette", "\(why) indicates a phone or tablet")) }
            if nameHas("macbook", "imac", "mac-mini", "macmini", "mac-studio", "macstudio", "mac-pro", "macpro", "-mbp", "-mba", "mbp-", "mba-") || name == "mac" || namePrefix("mac-") || nameSuffix("-mac") { hint(.mac, 2, L("\(why) désigne un Mac", "\(why) indicates a Mac")) }
            if namePrefix("desktop-", "laptop-", "win-", "pc-") || nameSuffix("-pc", "-win") || nameHas("windows") { hint(.windows, 2, L("\(why) suit la convention Windows", "\(why) follows the Windows naming convention")) }
            if nameHas("raspberrypi", "raspberry", "rpi", "ubuntu", "debian", "fedora", "archlinux", "nixos", "-linux") { hint(.linux, 2, L("\(why) désigne une machine Linux", "\(why) indicates a Linux machine")) }
            if nameHas("printer", "imprimante", "laserjet", "officejet", "pixma", "ecotank") || namePrefix("epson", "brother", "canon", "hp-") || title.contains("laserjet") || title.contains("officejet") { hint(.printer, 2, L("\(why) ou le titre de service désigne une imprimante", "\(why) or the service title indicates a printer")) }
            if name == "tv" || nameSuffix("-tv", "tv") || namePrefix("tv-") || nameHas("appletv", "apple-tv", "bravia", "chromecast", "firetv", "shield", "roku", "freebox-player") || title.contains("smart tv") { hint(.tv, 2, L("\(why) désigne un téléviseur ou un boîtier vidéo", "\(why) indicates a TV or media box")) }
            if nameHas("homepod", "sonos", "bose", "speaker", "enceinte") || namePrefix("echo-", "nest-") { hint(.speaker, 2, L("\(why) désigne une enceinte", "\(why) indicates a speaker")) }
            if ["router", "gateway", "hgw", "box", "routeur", "openwrt"].contains(name) || nameSuffix("-router", "-gateway", "-gw") || namePrefix("freebox", "livebox", "bbox", "sfrbox", "fritz", "udm", "usg", "gw-", "router", "routeur") { hint(.router, 2, L("\(why) désigne un routeur ou une box", "\(why) indicates a router or gateway")) }
            if nameHas("switch", "accesspoint", "access-point", "unifi-ap", "-uap", "uap-", "u6-", "u7-") || namePrefix("sw-", "ap-") || nameSuffix("-sw", "-ap") { hint(nameHas("nintendo") ? .console : .networkGear, 2, L("\(why) désigne un switch ou un point d'accès", "\(why) indicates a switch or access point")) }
            if name == "nas" || nameSuffix("-nas") || namePrefix("nas-", "diskstation", "synology", "qnap", "truenas", "unraid") { hint(.nas, 2, L("\(why) désigne un NAS", "\(why) indicates a NAS")) }
            if nameHas("camera", "ipcam", "doorbell", "-cam", "cam-", "webcam") || namePrefix("cam") || namePrefix("ring-", "arlo", "reolink") { hint(.camera, 2, L("\(why) désigne une caméra", "\(why) indicates a camera")) }
            if nameHas("playstation", "ps4", "ps5", "xbox", "nintendo") { hint(.console, 2, L("\(why) désigne une console de jeu", "\(why) indicates a game console")) }
            if nameHas("server", "serveur", "proxmox", "esxi", "vcenter") || namePrefix("srv-", "srv") || nameSuffix("-srv") { hint(.server, 2, L("\(why) désigne un serveur", "\(why) indicates a server")) }
            if nameHas("shelly", "tasmota", "sonoff", "tuya", "thermostat", "hue-", "bridge", "homekit", "aqara") || namePrefix("esp-", "esp_", "esp32", "esp8266") { hint(.iot, 2, L("\(why) désigne un objet connecté", "\(why) indicates an IoT device")) }
            if nameHas("watch") { hint(.watch, 2, L("\(why) désigne une montre", "\(why) indicates a watch")) }
        }

        // Vendor (IEEE registry). Ambiguous makers (Apple, Samsung, HP, Huawei, ASUS…) say nothing alone.
        if !vendor.isEmpty {
            let why = L("Fabricant \(host.vendor ?? "")", "Vendor \(host.vendor ?? "")")
            if vendorHas("freebox", "sagemcom", "technicolor", "arcadyan", "avm ", "avm gmbh", "askey", "sercomm", "hitron", "zte", "orange", "bouygues", "sfr", "iliad") { hint(.router, 2, L("\(why), fabricant de box", "\(why), residential gateway vendor")) }
            if vendorHas("ubiquiti", "netgear", "tp-link", "d-link", "cisco", "meraki", "juniper", "mikrotik", "aruba", "ruckus", "zyxel", "linksys", "belkin", "engenius", "edimax", "cambium", "draytek", "fortinet") { hint(.networkGear, 2, L("\(why), équipement réseau", "\(why), network equipment")) }
            if vendorHas("synology", "qnap", "western digital", "buffalo", "asustor", "terramaster") {
                let openStorage = !ports.isDisjoint(with: [445, 548, 2049, 5000, 5001, 6690])
                hint(.nas, openStorage ? 3 : 1, L("\(why), fabricant de NAS\(openStorage ? " avec un service de stockage ouvert" : "")", "\(why), NAS vendor\(openStorage ? " with an open storage service" : "")"))
            }
            if vendorHas("sonos", "bose", "denon", "marantz", "yamaha", "devialet", "bang & olufsen", "harman", "jbl", "teufel", "bluesound", "naim") { hint(.speaker, 2, L("\(why), fabricant d'enceintes", "\(why), speaker vendor")) }
            if vendorHas("hikvision", "dahua", "axis communications", "reolink", "arlo", "amcrest", "foscam", "wyze", "eufy", "annke") { hint(.camera, 2, L("\(why), fabricant de caméras", "\(why), camera vendor")) }
            if vendorHas("nintendo", "sony interactive") { hint(.console, 3, L("\(why), fabricant de consoles", "\(why), console vendor")) }
            if vendorHas("espressif", "tuya", "sonoff", "itead", "shelly", "allterco", "philips lighting", "signify", "lifx", "aqara", "lumi united", "somfy", "legrand", "delta dore", "tado", "ecobee", "nest labs", "ring llc", "netatmo") { hint(.iot, 2, L("\(why), fabricant d'objets connectés", "\(why), IoT vendor")) }
            if vendorHas("brother", "canon", "epson", "lexmark", "kyocera", "ricoh", "konica", "oki ", "xerox", "zebra") { hint(.printer, 2, L("\(why), fabricant d'imprimantes", "\(why), printer vendor")) }
            if vendorHas("raspberry", "beagle", "hardkernel", "pine64") { hint(.linux, 2, L("\(why), carte Linux", "\(why), Linux board")) }
            if vendorHas("dell", "lenovo", "acer", "micro-star", "gigabyte", "intel corporate", "fujitsu", "toshiba") { hint(.computer, 1, L("\(why), fabricant d'ordinateurs", "\(why), computer vendor")) }
            if vendorHas("oneplus", "oppo", "vivo", "motorola", "fairphone") { hint(.phone, 1, L("\(why), fabricant de téléphones", "\(why), phone vendor")) }
            if vendorHas("vestel", "lg electronics", "tcl", "hisense", "vizio", "roku", "tp vision") { hint(.tv, 2, L("\(why), fabricant de téléviseurs", "\(why), TV vendor")) }
            if vendorHas("samsung") { hint(.phone, 1, "\(why)"); hint(.tv, 1, "\(why)") }
        }

        // Bonjour service families.
        if services.contains("IPP") || services.contains("Imprimante") || services.contains("Impression") || services.contains("Printer") || services.contains("Printing") || services.contains("Scanner") { hint(.printer, 3, L("Service d'impression Bonjour", "Bonjour printing service")) }
        if services.contains("Chromecast") { hint(.tv, 2, L("Service Chromecast", "Chromecast service")) }
        if services.contains("AirPlay") { hint(.tv, 1, L("Service AirPlay", "AirPlay service")) }
        if services.contains("AirPlay audio"), !services.contains("AirPlay") { hint(.speaker, 2, L("Récepteur AirPlay audio seul", "Audio-only AirPlay receiver")) }
        if services.contains("HomeKit") { hint(.iot, 2, L("Accessoire HomeKit", "HomeKit accessory")) }
        if services.contains("Sonos") { hint(.speaker, 3, L("Service Sonos", "Sonos service")) }
        if services.contains("Philips Hue") { hint(.iot, 3, L("Pont Philips Hue", "Philips Hue bridge")) }
        if services.contains("Spotify Connect") { hint(.speaker, 1, "Spotify Connect") }
        if services.contains("Poste de travail") || services.contains("Workstation") { hint(.linux, 2, L("Poste de travail annoncé par Avahi", "Workstation advertised by Avahi")) }
        if services.contains("NDI") || services.contains("OSC") || services.contains("OSCQuery") { hint(.computer, 1, L("Logiciel de spectacle (NDI / OSC)", "Live show software (NDI / OSC)")) }
        if services.contains("SSH") || services.contains("SFTP") { hint(.computer, 1, L("Service SSH annoncé", "SSH service advertised")) }

        // Ports.
        if ports.contains(62078) { hint(.phone, 3, L("Port 62078 (synchronisation iOS)", "Port 62078 (iOS sync)")) }
        if ports.contains(445) && (ports.contains(135) || ports.contains(139)) { hint(.windows, 3, L("Services SMB et RPC/NetBIOS Windows", "Windows SMB and RPC/NetBIOS services")) }
        if ports.contains(3389) { hint(.windows, 2, L("Bureau à distance (3389)", "Remote Desktop (3389)")) }
        if ports.contains(5985) { hint(.windows, 2, "WinRM (5985)") }
        if ports.contains(9100) || ports.contains(515) { hint(.printer, 3, L("Port d'impression ouvert", "Open printing port")) }
        if ports.contains(631) && (vendorHas("brother", "canon", "epson", "hewlett", "hp inc") || nameHas("print")) { hint(.printer, 2, L("IPP avec une identité d'imprimante", "IPP with a printer identity")) }
        if ports.contains(548) { hint(.mac, 1, L("Partage de fichiers AFP (548)", "AFP file sharing (548)")) }
        if ports.contains(5900) && ports.contains(548) { hint(.mac, 1, L("Partage d'écran et AFP", "Screen Sharing and AFP")) }
        if ports.contains(22), !ports.contains(445) { hint(.computer, 1, L("SSH ouvert", "Open SSH")) }
        if !ports.isDisjoint(with: [32400, 8006, 10000, 9090, 3306, 5432, 6379, 27017, 9200, 6443, 2375]) {
            let formatted = PortScanner.formatList(ports.intersection([32400, 8006, 10000, 9090, 3306, 5432, 6379, 27017, 9200, 6443, 2375]).sorted())
            hint(.server, 2, L("Service de serveur ouvert (\(formatted))", "Open server service (\(formatted))"))
        }
        if ports.contains(554) || ports.contains(8554) { hint(.camera, 2, L("Flux RTSP (554)", "RTSP stream (554)")) }
        if ports.contains(1883) || ports.contains(8883) { hint(.iot, 2, L("MQTT ouvert", "Open MQTT")) }
        if ports.contains(161) && (ports.contains(80) || ports.contains(443)) { hint(.networkGear, 1, L("SNMP avec une interface web", "SNMP with a web interface")) }
        if ports.contains(8009) { hint(.tv, 2, "Google Cast (8009)") }
        if ports.contains(7000), !services.contains("AirPlay") { hint(.tv, 1, "AirPlay (7000)") }
        if ports.contains(3074) || !ports.isDisjoint(with: [9295, 9296, 9297]) { hint(.console, 2, L("Port de jeu en ligne", "Online gaming port")) }
        if ports.contains(5555) { hint(.phone, 1, L("Débogage Android (5555)", "Android debugging (5555)")) }

        // NetBIOS and TTL.
        if host.netbiosName != nil, host.workgroup != nil {
            hint(.windows, scores[.nas, default: 0] > 0 ? 1 : 2, L("Nom NetBIOS et groupe de travail", "NetBIOS name and workgroup"))
        }
        if let ttl = host.ttl {
            switch ttl {
            case 250...255:
                let reason = L("TTL \(ttl) typique des équipements réseau", "TTL \(ttl) typical of network gear")
                hint(.networkGear, 1, reason); hint(.router, 1, reason)
            case 120...128: hint(.windows, 1, L("TTL \(ttl) typique de Windows", "TTL \(ttl) typical of Windows"))
            default: break
            }
        }

        return decide(scores: scores, reasons: reasons, host: host, model: model, name: name)
    }

    private static func decide(scores: [DeviceType: Int], reasons: [DeviceType: [String]], host: Host, model: String, name: String) -> DeviceClassification {
        let ranked = scores.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
        guard let top = ranked.first else {
            return DeviceClassification(type: .unknown, confidence: .probable, reasons: [L("Pas assez d'indices pour estimer le type d'appareil.", "Not enough clues to estimate the device type.")], symbol: DeviceType.unknown.sfSymbol)
        }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        var winner = top.key
        var reasonList = reasons[winner] ?? []
        if top.value < 2 * runnerUp {
            // Close call. Computers of different stripes still make a computer.
            let contenders = ranked.filter { $0.value >= runnerUp }.map(\.key)
            guard contenders.allSatisfy(\.isComputer) else {
                return DeviceClassification(type: .unknown, confidence: .probable, reasons: [L("Indices contradictoires (\(contenders.map(\.label).joined(separator: " / "))) ; type laissé inconnu.", "Conflicting clues (\(contenders.map(\.label).joined(separator: " / "))); type left unknown.")], symbol: DeviceType.unknown.sfSymbol)
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
