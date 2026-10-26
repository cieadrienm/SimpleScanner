import Foundation

/// Supported UI languages across the Simple app family (`system`, `fr`, `en`).
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case fr
    case en

    public static let defaultsKey = "net.cieadrienm.simplescanner.language"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return L("Système", "System")
        case .fr: return "Français"
        case .en: return "English"
        }
    }

    /// Either `.fr` or `.en`, resolving `.system` against CLI, environment, and `Locale.preferredLanguages`.
    public var resolved: AppLanguage {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    public func resolve(
        preferredLanguages: [String],
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppLanguage {
        switch self {
        case .fr, .en:
            return self
        case .system:
            if let cli = Self.parseArguments(arguments), cli != .system {
                return cli
            }
            if let env = Self.parse(environment["SIMPLE_LANG"]), env != .system {
                return env
            }
            for code in preferredLanguages {
                let lower = code.lowercased()
                if lower.hasPrefix("fr") { return .fr }
                if lower.hasPrefix("en") { return .en }
            }
            return .fr
        }
    }

    /// Resolved two-letter language code (`"fr"` or `"en"`).
    public var resolvedCode: String {
        resolved == .en ? "en" : "fr"
    }

    public var isEnglish: Bool {
        resolved == .en
    }

    public var locale: Locale {
        Locale(identifier: resolved == .en ? "en_US" : "fr_FR")
    }

    public static func parse(_ value: String?) -> AppLanguage? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        if trimmed == "system" || trimmed == "auto" { return .system }
        if trimmed == "fr" || trimmed.hasPrefix("fr-") || trimmed.hasPrefix("fr_") || trimmed == "french" || trimmed == "francais" || trimmed == "français" {
            return .fr
        }
        if trimmed == "en" || trimmed.hasPrefix("en-") || trimmed.hasPrefix("en_") || trimmed == "english" {
            return .en
        }
        return nil
    }

    public static func parseArguments(_ arguments: [String]) -> AppLanguage? {
        for (index, arg) in arguments.enumerated() {
            if (arg == "--lang" || arg == "-AppleLanguage"), index + 1 < arguments.count,
               let parsed = parse(arguments[index + 1]) {
                return parsed
            }
            if arg.hasPrefix("--lang="),
               let parsed = parse(String(arg.dropFirst("--lang=".count))) {
                return parsed
            }
        }
        return nil
    }

    /// Detects the initial language from `--lang`, `SIMPLE_LANG`, or `UserDefaults`.
    public static func detect(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> AppLanguage {
        if let cli = parseArguments(arguments) {
            return cli
        }
        if let env = environment["SIMPLE_LANG"], let parsed = parse(env) {
            return parsed
        }
        if let stored = defaults.string(forKey: defaultsKey), let parsed = parse(stored) {
            return parsed
        }
        return .system
    }

    public static var current: AppLanguage {
        get { Localization.current }
        set { Localization.current = newValue }
    }
}

/// Global language selector persisted in `UserDefaults` (`net.cieadrienm.simplescanner.language` and `AppleLanguages`).
public enum Localization {
    public static let defaultsKey = AppLanguage.defaultsKey
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: AppLanguage = AppLanguage.detect()

    public static var current: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _current
        }
        set {
            set(newValue, defaults: .standard, persist: true)
        }
    }

    public static func set(_ newValue: AppLanguage, defaults: UserDefaults = .standard, persist: Bool = true) {
        lock.lock()
        _current = newValue
        lock.unlock()
        guard persist else { return }
        defaults.set(newValue.rawValue, forKey: defaultsKey)
        switch newValue {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .fr:
            defaults.set(["fr", "en"], forKey: "AppleLanguages")
        case .en:
            defaults.set(["en", "fr"], forKey: "AppleLanguages")
        }
    }

    public static var isEnglish: Bool {
        current.isEnglish
    }
}

/// Returns `en` when the active language is English, otherwise `fr`.
@inline(__always)
public func L(_ fr: String, _ en: String) -> String {
    Localization.isEnglish ? en : fr
}
