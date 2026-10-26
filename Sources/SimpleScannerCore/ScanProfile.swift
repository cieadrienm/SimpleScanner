import Foundation

public enum ScanProfile: String, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case deep

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quick: L("Rapide", "Fast")
        case .standard: L("Standard", "Standard")
        case .deep: L("Approfondi", "Deep")
        }
    }

    public var description: String {
        switch self {
        case .quick: L("Ping ICMP et table ARP : le plus rapide.", "ICMP ping and ARP table: the fastest.")
        case .standard: L("Ping, ARP, NetBIOS et repli TCP pour les hôtes qui bloquent le ping.", "Ping, ARP, NetBIOS, and TCP fallback for hosts blocking ping.")
        case .deep: L("Standard, puis analyse des ports courants et lecture des bannières.", "Standard, plus common port scan and banner grabbing.")
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
