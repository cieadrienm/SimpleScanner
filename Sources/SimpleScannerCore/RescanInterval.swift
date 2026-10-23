import Foundation

public enum RescanInterval: String, CaseIterable, Identifiable, Sendable {
    case off
    case s30
    case m1
    case m5
    case m15

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .s30: 30
        case .m1: 60
        case .m5: 300
        case .m15: 900
        }
    }

    public var label: String {
        switch self {
        case .off: "Désactivé"
        case .s30: "30 s"
        case .m1: "1 min"
        case .m5: "5 min"
        case .m15: "15 min"
        }
    }

    public var menuLabel: String {
        switch self {
        case .off: "Rescan automatique désactivé"
        default: "Rescan toutes les \(label)"
        }
    }
}
