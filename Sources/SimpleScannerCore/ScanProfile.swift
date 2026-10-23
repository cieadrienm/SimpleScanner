import Foundation

public enum ScanProfile: String, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case deep

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quick: "Rapide"
        case .standard: "Standard"
        case .deep: "Approfondi"
        }
    }

    public var description: String {
        switch self {
        case .quick: "Ping ICMP et table ARP : le plus rapide."
        case .standard: "Ping, ARP, NetBIOS et repli TCP pour les hôtes qui bloquent le ping."
        case .deep: "Standard, puis analyse des ports courants et lecture des bannières."
        }
    }

    public var symbol: String {
        switch self {
        case .quick: "hare"
        case .standard: "scope"
        case .deep: "magnifyingglass"
        }
    }

    public var useTCPFallback: Bool { self != .quick }
    public var autoPortScan: Bool { self == .deep }
    /// Standard / Deep run an extra UDP-137 query to pull NetBIOS computer name and workgroup.
    public var includeNetBIOS: Bool { self != .quick }
}
