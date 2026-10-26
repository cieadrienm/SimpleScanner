import AppKit
import SimpleScannerCore
import SwiftUI

/// The dark palette of the Simple family (SimpleAudio, Montage, OSCScore), plus the scanner's states.
enum Theme {
    static let background = NSColor(hex: 0x111317)
    static let panel = NSColor(hex: 0x16191E)
    static let lane = NSColor(hex: 0x181B21)
    static let laneAlt = NSColor(hex: 0x1B1F26)
    static let laneSelected = NSColor(hex: 0x1F2530)
    static let header = NSColor(hex: 0x14171C)
    static let separator = NSColor(hex: 0x0B0C0F)
    static let gridMinor = NSColor(white: 1, alpha: 0.035)
    static let gridMajor = NSColor(white: 1, alpha: 0.085)
    static let text = NSColor(hex: 0xE6E8EC)
    static let textDim = NSColor(hex: 0x8A919E)
    static let textFaint = NSColor(hex: 0x565D6A)
    static let accent = NSColor(hex: 0xFFB454)
    static let alive = NSColor(hex: 0x9ECE6A)
    static let arp = NSColor(hex: 0x7AA2F7)
    static let tcp = NSColor(hex: 0x5CE1E6)
    static let bonjour = NSColor(hex: 0xC792EA)
    static let changed = NSColor(hex: 0xF2D96B)
    static let danger = NSColor(hex: 0xFF5C57)
    static let selection = NSColor.white

    /// Colour of a device's status dot.
    static func status(_ host: Host) -> NSColor {
        switch host.status {
        case .scanning: return accent
        case .dead: return textFaint
        case .alive:
            switch host.discoveredBy {
            case .arp: return arp
            case .tcp: return tcp
            default: return alive
            }
        }
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xff) / 255,
            green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    var swiftUI: Color { Color(nsColor: self) }
}

enum Format {
    /// `12 ms`, `0,4 ms`, `—`.
    static func latency(_ ms: Double?) -> String {
        guard let ms, ms.isFinite else { return "—" }
        let dec = L(",", ".")
        if ms < 1 { return String(format: "%.1f ms", ms).replacingOccurrences(of: ".", with: dec) }
        if ms < 10 { return String(format: "%.1f ms", ms).replacingOccurrences(of: ".", with: dec) }
        return String(format: "%.0f ms", ms)
    }

    /// `2,4 s`, `0:12`.
    static func elapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1f s", seconds).replacingOccurrences(of: ".", with: L(",", ".")) }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Operating-system hint from an ICMP TTL.
    static func ttlHint(_ ttl: Int?) -> String? {
        guard let ttl else { return nil }
        switch ttl {
        case 60...64: return "Unix / Apple / Linux (TTL \(ttl))"
        case 120...128: return "Windows (TTL \(ttl))"
        case 250...255: return L("Équipement réseau (TTL \(ttl))", "Network gear (TTL \(ttl))")
        default: return "TTL \(ttl)"
        }
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) " + (n > 1 ? (plural ?? singular + "s") : singular)
    }
}
