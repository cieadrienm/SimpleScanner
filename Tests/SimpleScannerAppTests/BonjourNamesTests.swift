import XCTest
@testable import SimpleScanner
@testable import SimpleScannerCore

final class BonjourNamesTests: XCTestCase {
    func testCleanNameStripsMachinePrefixesAndHashes() {
        XCTAssertEqual(MDNSDiscovery.cleanName("3AB608DB6D2A@MacbookProAd", type: "_raop._tcp"), "MacbookProAd")
        XCTAssertEqual(MDNSDiscovery.cleanName("Sonos-949F3EAB12CD@Salon", type: "_sonos._tcp"), "Salon")
        XCTAssertEqual(MDNSDiscovery.cleanName("Chromecast-0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d", type: "_googlecast._tcp"), "Chromecast")
        XCTAssertEqual(MDNSDiscovery.cleanName("regie [dc:a6:32:7b:90:14]", type: "_workstation._tcp"), "regie")
        XCTAssertEqual(MDNSDiscovery.cleanName("Salon (2)", type: "_airplay._tcp"), "Salon")
        XCTAssertEqual(MDNSDiscovery.cleanName("MacbookProAd", type: "_smb._tcp"), "MacbookProAd")
        XCTAssertEqual(MDNSDiscovery.cleanName("osc@studio", type: "_osc._udp"), "osc@studio")
    }

    func testIdentityServicesNameTheDeviceBeforeAirPlayAudio() {
        let records = [
            MDNSDiscovery.ServiceRecord(displayType: "AirPlay audio", serviceType: "_raop._tcp", name: "MacbookProAd", ip: "192.168.0.131"),
            MDNSDiscovery.ServiceRecord(displayType: "HTTP", serviceType: "_http._tcp", name: "Freebox Server", ip: "192.168.0.131"),
            MDNSDiscovery.ServiceRecord(displayType: "SMB", serviceType: "_smb._tcp", name: "MacbookProAd", ip: "192.168.0.131"),
            MDNSDiscovery.ServiceRecord(displayType: "Infos appareil", serviceType: "_device-info._tcp", name: "MacbookProAd", ip: "192.168.0.131"),
        ]
        XCTAssertEqual(MDNSDiscovery.names(from: records), ["MacbookProAd", "Freebox Server"])
    }

    func testChipActions() {
        XCTAssertEqual(HostActions.action(forService: "SFTP", port: 22)?.connection, .sftp)
        XCTAssertEqual(HostActions.action(forService: "OSCQuery", port: 9231)?.port, 9231)
        XCTAssertEqual(HostActions.action(forService: "Partage d'écran", port: 5900)?.connection, .vnc)
        XCTAssertNil(HostActions.action(forService: "AirPlay", port: 7000))
        XCTAssertEqual(HostActions.action(forPort: 8443)?.connection, .https)
        XCTAssertEqual(HostActions.action(forPort: 8443)?.port, 8443)
        XCTAssertEqual(HostActions.action(forPort: 445)?.connection, .smb)
        XCTAssertNil(HostActions.action(forPort: 62078))
    }
}
