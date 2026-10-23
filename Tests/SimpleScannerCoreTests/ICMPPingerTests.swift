import XCTest
@testable import SimpleScannerCore

final class ICMPPingerTests: XCTestCase {
    func testChecksumMatchesRFC1071Example() {
        // Header 0x4500 0x0073 0x0000 0x4000 0x4011 [0x0000] 0xc0a8 0x0001 0xc0a8 0x00c7 → 0xb861
        let bytes: [UInt8] = [0x45, 0x00, 0x00, 0x73, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0xc0, 0xa8, 0x00, 0x01, 0xc0, 0xa8, 0x00, 0xc7]
        XCTAssertEqual(ICMPPinger.checksum(bytes), 0xb861)
    }

    func testLoopbackEchoReturnsReplyWithTTL() async throws {
        let pinger = try XCTUnwrap(ICMPPinger.shared)
        let reply = await pinger.ping(IPv4.uint32(from: "127.0.0.1")!, timeout: .seconds(2))
        XCTAssertNotNil(reply)
        XCTAssertEqual(reply?.ttl, 64)
        XCTAssertLessThan(reply?.rttMs ?? 1000, 500)
    }

    func testSweepFindsLoopbackAndMissesUnusedAlias() async throws {
        let pinger = try XCTUnwrap(ICMPPinger.shared)
        let found = Found()
        let report = await pinger.sweep([IPv4.uint32(from: "127.0.0.1")!, IPv4.uint32(from: "127.0.0.2")!], replyTimeout: .milliseconds(600), onReply: { found.add($0.address) })
        XCTAssertEqual(report.sent, 2)
        XCTAssertEqual(report.replies, 1)
        XCTAssertEqual(found.values, [IPv4.uint32(from: "127.0.0.1")!])
    }

    func testDiscoverReportsLoopbackAlive() async {
        let result = await NetworkScanner.discover("127.0.0.1")
        XCTAssertEqual(result?.via, .icmp)
    }

    private final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private var set = Set<UInt32>()
        func add(_ v: UInt32) { lock.withLock { _ = set.insert(v) } }
        var values: Set<UInt32> { lock.withLock { set } }
    }
}
