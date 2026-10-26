import Foundation
import XCTest
@testable import SimpleScanner
@testable import SimpleScannerCore

@MainActor
final class SimpleUpdaterTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SimpleUpdater.isNewerVersion("1.1.0", than: "1.0.0"))
        XCTAssertTrue(SimpleUpdater.isNewerVersion("v1.0.1", than: "1.0.0"))
        XCTAssertTrue(SimpleUpdater.isNewerVersion("2.0", than: "1.9.9"))
        XCTAssertFalse(SimpleUpdater.isNewerVersion("1.0.0", than: "1.0.0"))
        XCTAssertFalse(SimpleUpdater.isNewerVersion("1.0", than: "1.0.0"))
        XCTAssertFalse(SimpleUpdater.isNewerVersion("0.9.0", than: "1.0.0"))

        // Build number tie-breaker when semantic versions match
        XCTAssertTrue(SimpleUpdater.isNewerVersion("0.9.0", candidateBuild: 42, than: "0.9.0", currentBuild: 41))
        XCTAssertFalse(SimpleUpdater.isNewerVersion("0.9.0", candidateBuild: 41, than: "0.9.0", currentBuild: 41))
        XCTAssertFalse(SimpleUpdater.isNewerVersion("0.9.0", candidateBuild: 40, than: "0.9.0", currentBuild: 41))
    }

    func testParseGitHubReleaseJSON() throws {
        let json = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/cieadrienm/SimpleScanner/releases/tag/v1.2.0",
          "body": "Faster ARP sweep\\nSHA-256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "assets": [
            {
              "name": "SimpleScanner-1.2.0.dmg",
              "browser_download_url": "https://github.com/cieadrienm/SimpleScanner/releases/download/v1.2.0/SimpleScanner-1.2.0.dmg"
            },
            {
              "name": "SimpleScanner-1.2.0.zip",
              "browser_download_url": "https://github.com/cieadrienm/SimpleScanner/releases/download/v1.2.0/SimpleScanner-1.2.0.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let release = try SimpleUpdater.parseGitHubRelease(data: json)
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/cieadrienm/SimpleScanner/releases/download/v1.2.0/SimpleScanner-1.2.0.zip")
        XCTAssertEqual(release.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertTrue(release.notes.contains("Faster ARP sweep"))
    }

    func testParseGitHubReleaseFailsWithoutZipAsset() {
        let json = """
        {
          "tag_name": "v1.2.0",
          "body": "Notes",
          "assets": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try SimpleUpdater.parseGitHubRelease(data: json)) { error in
            XCTAssertEqual(error as? SimpleUpdater.UpdaterError, .noZipAssetFound)
        }
    }

    func testParseMultiAppAndSingleObjectManifest() throws {
        let multiAppJSON = """
        {
          "net.cieadrienm.simplescanner": {
            "version": "1.3.0",
            "build": 55,
            "url": "https://example.com/SimpleScanner-1.3.0.zip",
            "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "notes_fr": "Nouveautés FR",
            "notes_en": "What's new EN"
          }
        }
        """.data(using: .utf8)!

        let relMulti = try SimpleUpdater.parseManifest(data: multiAppJSON, bundleID: "net.cieadrienm.simplescanner")
        XCTAssertEqual(relMulti.version, "1.3.0")
        XCTAssertEqual(relMulti.build, 55)
        XCTAssertEqual(relMulti.downloadURL.absoluteString, "https://example.com/SimpleScanner-1.3.0.zip")
        XCTAssertEqual(relMulti.sha256, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        XCTAssertEqual(relMulti.notesFR, "Nouveautés FR")
        XCTAssertEqual(relMulti.notesEN, "What's new EN")

        let singleObjectJSON = """
        {
          "version": "v1.4.0",
          "build": "60",
          "url": "https://example.com/SimpleScanner-1.4.0.zip",
          "notes": "Unified notes"
        }
        """.data(using: .utf8)!

        let relSingle = try SimpleUpdater.parseManifest(data: singleObjectJSON)
        XCTAssertEqual(relSingle.version, "1.4.0")
        XCTAssertEqual(relSingle.build, 60)
        XCTAssertNil(relSingle.sha256)
        XCTAssertEqual(relSingle.notesFR, "Unified notes")
        XCTAssertEqual(relSingle.notesEN, "Unified notes")
    }

    func testSHA256Verification() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("simplescanner-sha256-\(UUID().uuidString).bin")
        let payload = Data("SimpleScanner test payload".utf8)
        try payload.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let expected = SimpleUpdater.sha256Hex(of: payload)
        XCTAssertEqual(expected.count, 64)
        XCTAssertTrue(try SimpleUpdater.verifySHA256(fileURL: tempURL, expectedHex: expected))
        XCTAssertTrue(try SimpleUpdater.verifySHA256(fileURL: tempURL, expectedHex: expected.uppercased()))
        XCTAssertTrue(try SimpleUpdater.verifySHA256(fileURL: tempURL, expectedHex: nil))
        XCTAssertTrue(try SimpleUpdater.verifySHA256(fileURL: tempURL, expectedHex: "   "))
        XCTAssertFalse(try SimpleUpdater.verifySHA256(fileURL: tempURL, expectedHex: String(repeating: "0", count: 64)))
    }

    func testPerformCheckTransitionsState() async {
        let suiteName = "SimpleUpdaterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manifestData = """
        {
          "version": "2.0.0",
          "build": 99,
          "url": "https://example.com/SimpleScanner-2.0.0.zip",
          "notes_fr": "Version 2.0",
          "notes_en": "Version 2.0"
        }
        """.data(using: .utf8)!

        let updater = SimpleUpdater(
            currentVersion: "0.9.0",
            currentBuild: 10,
            defaults: defaults,
            dataFetcher: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (manifestData, response)
            }
        )

        await updater.performCheck(
            silent: false,
            environment: ["SIMPLE_UPDATE_URL": "https://example.com/manifest.json"]
        )

        if case .updateAvailable(let release) = updater.state {
            XCTAssertEqual(release.version, "2.0.0")
            XCTAssertEqual(release.build, 99)
        } else {
            XCTFail("Expected .updateAvailable, got \(updater.state)")
        }

        let upToDateUpdater = SimpleUpdater(
            currentVersion: "2.0.0",
            currentBuild: 100,
            defaults: defaults,
            dataFetcher: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (manifestData, response)
            }
        )

        await upToDateUpdater.performCheck(
            silent: false,
            environment: ["SIMPLE_UPDATE_URL": "https://example.com/manifest.json"]
        )
        XCTAssertEqual(upToDateUpdater.state, .upToDate("2.0.0"))
    }
}
