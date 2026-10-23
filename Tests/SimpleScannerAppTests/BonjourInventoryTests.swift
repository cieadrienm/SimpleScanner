import XCTest
@testable import SimpleScanner
@testable import SimpleScannerCore

final class BonjourInventoryTests: XCTestCase {
    @MainActor func testBonjourRemovalRejectsLateResults() {
        var inventory = BonjourInventory()
        let id = "_http._tcp|local.|Printer|1"
        _ = inventory.reconcile(ids: [id], type: "_http._tcp")
        let token = inventory.tokens[id]!
        let record = MDNSDiscovery.ServiceRecord(displayType: "HTTP", serviceType: "_http._tcp", name: "Printer", ip: "192.0.2.1")
        inventory.accept(record, id: id, token: token)
        XCTAssertEqual(inventory.records.count, 1)
        _ = inventory.reconcile(ids: [], type: "_http._tcp")
        inventory.accept(record, id: id, token: token)
        XCTAssertTrue(inventory.records.isEmpty)
        _ = inventory.reconcile(ids: [id], type: "_http._tcp")
        inventory.accept(record, id: id, token: token)
        XCTAssertTrue(inventory.records.isEmpty)
    }
}
