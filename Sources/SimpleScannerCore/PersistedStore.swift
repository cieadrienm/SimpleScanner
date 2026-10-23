import Foundation

public struct SavedRange: Codable, Hashable, Identifiable, Sendable {
    public var range: String
    public var name: String?

    public init(range: String, name: String?) {
        self.range = range
        self.name = name
    }

    public var id: String { range }

    public var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return range
    }
}

/// Labels and favourite ranges, in the user's defaults (`net.cieadrienm.simplescanner`).
public enum PersistedStore {
    private static let labelsKey = "simplescanner.labels"
    private static let savedRangesKey = "simplescanner.savedRanges"

    nonisolated(unsafe) public static var defaults: UserDefaults = .standard

    public static func loadLabels() -> [String: String] {
        defaults.dictionary(forKey: labelsKey) as? [String: String] ?? [:]
    }

    public static func saveLabels(_ labels: [String: String]) {
        if labels.isEmpty {
            defaults.removeObject(forKey: labelsKey)
        } else {
            defaults.set(labels, forKey: labelsKey)
        }
    }

    public static func loadRanges() -> [SavedRange] {
        if let data = defaults.data(forKey: savedRangesKey),
           let decoded = try? JSONDecoder().decode([SavedRange].self, from: data) {
            return decoded
        }
        return []
    }

    public static func saveRanges(_ ranges: [SavedRange]) {
        if ranges.isEmpty {
            defaults.removeObject(forKey: savedRangesKey)
            return
        }
        if let data = try? JSONEncoder().encode(ranges) {
            defaults.set(data, forKey: savedRangesKey)
        }
    }
}
