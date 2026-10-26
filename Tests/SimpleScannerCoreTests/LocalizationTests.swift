import XCTest
@testable import SimpleScannerCore

final class LocalizationTests: XCTestCase {
    func testDetectionFromCLIArgumentsAndEnvironment() throws {
        let suiteName = "net.cieadrienm.simplescanner.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            AppLanguage.detect(
                arguments: ["SimpleScanner", "--lang", "en"],
                environment: [:],
                defaults: defaults
            ),
            .en
        )
        XCTAssertEqual(
            AppLanguage.detect(
                arguments: ["SimpleScanner", "--lang=fr"],
                environment: ["SIMPLE_LANG": "en"],
                defaults: defaults
            ),
            .fr
        )
        XCTAssertEqual(
            AppLanguage.detect(
                arguments: ["SimpleScanner"],
                environment: ["SIMPLE_LANG": "en_US"],
                defaults: defaults
            ),
            .en
        )
        XCTAssertEqual(
            AppLanguage.detect(
                arguments: ["SimpleScanner"],
                environment: [:],
                defaults: defaults
            ),
            .system
        )
        XCTAssertEqual(
            AppLanguage.system.resolve(
                preferredLanguages: ["en-US", "fr-FR"],
                arguments: ["SimpleScanner"],
                environment: [:]
            ),
            .en
        )
        XCTAssertEqual(
            AppLanguage.system.resolve(
                preferredLanguages: ["fr-FR", "en-US"],
                arguments: ["SimpleScanner"],
                environment: [:]
            ),
            .fr
        )
    }

    func testLanguagePersistenceAndSwitching() throws {
        let previous = Localization.current
        defer { Localization.set(previous, persist: false) }

        let suiteName = "net.cieadrienm.simplescanner.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        Localization.set(.en, defaults: defaults)
        XCTAssertEqual(Localization.current, .en)
        XCTAssertEqual(Localization.current.resolved, .en)
        XCTAssertEqual(L("Scanner", "Scan"), "Scan")
        XCTAssertEqual(ScanProfile.quick.label, "Fast")
        XCTAssertEqual(DeviceType.router.label, "Router / gateway")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en", "fr"])

        Localization.set(.fr, defaults: defaults)
        XCTAssertEqual(Localization.current, .fr)
        XCTAssertEqual(Localization.current.resolved, .fr)
        XCTAssertEqual(L("Scanner", "Scan"), "Scanner")
        XCTAssertEqual(ScanProfile.quick.label, "Rapide")
        XCTAssertEqual(DeviceType.router.label, "Routeur / box")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "fr")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["fr", "en"])
    }
}
