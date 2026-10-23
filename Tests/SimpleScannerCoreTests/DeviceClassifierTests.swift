import XCTest
@testable import SimpleScannerCore

final class DeviceClassifierTests: XCTestCase {

    private func host(
        ip: String = "10.0.0.1",
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil
    ) -> Host {
        Host(
            ip: ip,
            hostname: hostname,
            mac: mac,
            vendor: vendor,
            openPorts: openPorts,
            serviceTitle: serviceTitle,
            status: .alive
        )
    }

    // MARK: - Routers

    func testRouterByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "HUAWEI TECHNOLOGIES CO.,LTD")), .unknown)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "TP-LINK TECHNOLOGIES CO.,LTD.")), .networkGear)
        XCTAssertEqual(DeviceClassifier.assessment(host(vendor: "NETGEAR")).confidence, .probable)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "ASUSTeK COMPUTER INC.")), .unknown)
    }

    func testRouterByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "hgw.local")), .router)
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "gateway.lan")), .router)
    }

    // MARK: - Printer

    func testPrinterByPort9100() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [9100])), .printer)
    }

    func testPrinterByPort631IPP() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [631])), .unknown)
    }

    func testPrinterByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Hewlett Packard")), .unknown)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Brother Industries")), .printer)
        XCTAssertEqual(DeviceClassifier.assessment(host(vendor: "Canon Inc.")).confidence, .probable)
    }

    // MARK: - TV

    func testVestelTV() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Vestel Elektronik San ve Tic. A.S.")), .tv)
    }

    func testTVByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "livingroom-tv.local")), .tv)
    }

    // MARK: - NAS

    func testSynologyNAS() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Synology Incorporated", openPorts: [5000])), .nas)
    }

    func testNASByPort() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [5000])), .unknown)
    }

    // MARK: - Phone

    func testIPhoneByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "iphone.local", vendor: "Apple, Inc.")), .phone)
    }

    func testIPad() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "ipad.local", vendor: "Apple, Inc.")), .phone)
    }

    // MARK: - Mac

    func testMacByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "macbook.local", vendor: "Apple, Inc.")), .mac)
    }

    // MARK: - Roles, ports, confidence

    func testGatewayIsARouterWhateverTheVendor() {
        var gateway = host(vendor: "HUAWEI TECHNOLOGIES CO.,LTD")
        gateway.role = .gateway
        let result = DeviceClassifier.assessment(gateway)
        XCTAssertEqual(result.type, .router)
        XCTAssertTrue(result.isCertain)
    }

    func testThisMacWinsOverOtherHints() {
        var mine = host(hostname: "desktop-of-adrien.local", vendor: "Dell Inc.")
        mine.role = .thisMac
        XCTAssertEqual(DeviceClassifier.classify(mine), .mac)
    }

    func testUbiquitiIsNetworkGearUnlessGateway() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Ubiquiti Inc")), .networkGear)
        var gateway = host(vendor: "Ubiquiti Inc")
        gateway.role = .gateway
        XCTAssertEqual(DeviceClassifier.classify(gateway), .router)
    }

    func testIOSLockdownPortIsAPhone() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [62078])), .phone)
        XCTAssertTrue(DeviceClassifier.assessment(host(openPorts: [62078])).isCertain)
    }

    func testComputerFamiliesMergeInsteadOfConflicting() {
        var pi = host(vendor: "Raspberry Pi Trading Ltd", openPorts: [22])
        pi.services = ["SSH"]
        XCTAssertEqual(DeviceClassifier.classify(pi), .linux)
        var pc = host(hostname: "desktop-7h2k.local", vendor: "Dell Inc.")
        pc.ttl = 128
        XCTAssertEqual(DeviceClassifier.classify(pc), .windows)
    }

    func testCloseCallStaysUnknown() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Samsung Electronics Co.,Ltd")), .unknown)
    }

    func testCameraByVendorAndRTSP() {
        let cam = host(vendor: "Hikvision Digital Technology", openPorts: [80, 554])
        XCTAssertEqual(DeviceClassifier.classify(cam), .camera)
        XCTAssertTrue(DeviceClassifier.assessment(cam).isCertain)
    }

    // MARK: - Unknown

    func testEmptyHost() {
        XCTAssertEqual(DeviceClassifier.classify(host()), .unknown)
    }

    func testRandomMACWithNothing() {
        // Locally-administered MAC, no other signals.
        XCTAssertEqual(DeviceClassifier.classify(host(mac: "AA:BB:CC:DD:EE:FF")), .unknown)
    }

    // MARK: - Symbols

    func testAllDeviceTypesHaveSymbols() {
        for type in DeviceType.allCases {
            XCTAssertFalse(type.sfSymbol.isEmpty, "\(type) missing SF Symbol")
            XCTAssertFalse(type.label.isEmpty, "\(type) missing label")
        }
    }
}
