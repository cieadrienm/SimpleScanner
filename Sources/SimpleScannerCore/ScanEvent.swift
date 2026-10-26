import Foundation

public enum ScanEvent: Sendable {
    case phase(ScanPhase)
    case progress(scanned: Int, total: Int)
    case host(Host)
    case warning(ScanWarning)
    /// How the ICMP sweep went: for the headless mode's log and the About sheet.
    case sweep(sent: Int, replies: Int, rejected: Int, arpNeighbours: Int)
    case done
}

public enum ScanWarning: Sendable, Hashable {
    /// Empty results can reflect routing, cache state, or OS privacy restrictions.
    case arpFailed(String)
    case arpEmpty
    /// At least one banner fetch (HTTP title / SSH greeting) failed.
    case bannerFetchFailures(count: Int)
    /// macOS refused our packets to the local network (Privacy › Local Network).
    case localNetworkDenied
    /// The kernel refused an ICMP datagram socket; discovery fell back to TCP probes.
    case icmpUnavailable

    public var label: String {
        switch self {
        case .arpFailed(let message): return message
        case .arpEmpty: return L("Adresses MAC indisponibles (table ARP vide)", "MAC addresses unavailable (empty ARP table)")
        case .bannerFetchFailures(let n): return n == 1 ? L("1 bannière illisible", "1 unreadable banner") : L("\(n) bannières illisibles", "\(n) unreadable banners")
        case .localNetworkDenied: return L("Accès au réseau local refusé par macOS", "Local network access denied by macOS")
        case .icmpUnavailable: return L("Ping ICMP indisponible", "ICMP ping unavailable")
        }
    }

    public var detail: String {
        switch self {
        case .arpFailed(let message): return message
        case .arpEmpty:
            return L(
                "macOS n'a renvoyé aucune entrée ARP. Les appareils derrière un routeur n'ont pas d'entrée locale ; un second scan sur un réseau calme peut en révéler davantage.",
                "macOS returned no ARP entries. Devices behind a router have no local entry; a second scan on a quiet network may reveal more."
            )
        case .bannerFetchFailures:
            return L(
                "Le titre HTTP ou la bannière SSH n'a pas pu être lu. Les bannières sont un complément : la découverte n'en dépend pas.",
                "The HTTP title or SSH banner could not be read. Banners are supplemental: discovery does not depend on them."
            )
        case .localNetworkDenied:
            return L(
                "Autorisez SimpleScanner dans Réglages Système › Confidentialité et sécurité › Réseau local, puis relancez le scan.",
                "Allow SimpleScanner in System Settings › Privacy & Security › Local Network, then run the scan again."
            )
        case .icmpUnavailable:
            return L(
                "macOS a refusé l'ouverture d'un socket ICMP. La découverte repose sur la table ARP et des sondes TCP, plus lentes.",
                "macOS refused to open an ICMP socket. Discovery falls back to the ARP table and slower TCP probes."
            )
        }
    }
}

public enum ScanPhase: String, Sendable {
    case discovery = "Découverte des appareils"
    case enrichment = "Résolution des noms"
    case ports = "Analyse des ports"
    case banners = "Lecture des bannières"

    public var label: String {
        switch self {
        case .discovery: L("Découverte des appareils", "Discovering devices")
        case .enrichment: L("Résolution des noms", "Resolving names")
        case .ports: L("Analyse des ports", "Scanning ports")
        case .banners: L("Lecture des bannières", "Reading banners")
        }
    }
}
