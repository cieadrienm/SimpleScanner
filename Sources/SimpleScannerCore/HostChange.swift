import Foundation

public enum HostChange: Equatable, Sendable {
    case new
    case modified(fields: [ChangedField])
    case missing(record: ScanSnapshot.HostRecord)

    public enum ChangedField: String, Sendable, Equatable {
        case hostname
        case mac
        case vendor
        case openPorts
        case serviceTitle

        public var label: String {
            switch self {
            case .hostname: "nom"
            case .mac: "MAC"
            case .vendor: "fabricant"
            case .openPorts: "ports"
            case .serviceTitle: "service"
            }
        }
    }

    public var sfSymbol: String {
        switch self {
        case .new: "plus.circle.fill"
        case .modified: "circle.lefthalf.filled"
        case .missing: "minus.circle.fill"
        }
    }

    public var label: String {
        switch self {
        case .new: "Nouveau"
        case .modified(let fields): "Modifié : " + fields.map(\.label).joined(separator: ", ")
        case .missing: "Disparu"
        }
    }
}
