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
        case .arpEmpty: return "Adresses MAC indisponibles (table ARP vide)"
        case .bannerFetchFailures(let n): return n == 1 ? "1 bannière illisible" : "\(n) bannières illisibles"
        case .localNetworkDenied: return "Accès au réseau local refusé par macOS"
        case .icmpUnavailable: return "Ping ICMP indisponible"
        }
    }

    public var detail: String {
        switch self {
        case .arpFailed(let message): return message
        case .arpEmpty:
            return "macOS n'a renvoyé aucune entrée ARP. Les appareils derrière un routeur n'ont pas d'entrée locale ; un second scan sur un réseau calme peut en révéler davantage."
        case .bannerFetchFailures:
            return "Le titre HTTP ou la bannière SSH n'a pas pu être lu. Les bannières sont un complément : la découverte n'en dépend pas."
        case .localNetworkDenied:
            return "Autorisez SimpleScanner dans Réglages Système › Confidentialité et sécurité › Réseau local, puis relancez le scan."
        case .icmpUnavailable:
            return "macOS a refusé l'ouverture d'un socket ICMP. La découverte repose sur la table ARP et des sondes TCP, plus lentes."
        }
    }
}

public enum ScanPhase: String, Sendable {
    case discovery = "Découverte des appareils"
    case enrichment = "Résolution des noms"
    case ports = "Analyse des ports"
    case banners = "Lecture des bannières"
}
