import AppKit
import Foundation
import SimpleScannerCore

/// `SimpleScanner --self-test`: the engine, the model and the window, without touching the network
/// beyond this Mac's loopback. Also run by `swift test`.
@MainActor
enum SelfTest {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    static func runAndExit() -> Never {
        Task { @MainActor in
            do {
                try await run()
                print("SELF-TEST PASSED")
                exit(0)
            } catch {
                fputs("SELF-TEST FAILED: \(error)\n", stderr)
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(1)
    }

    static func run() async throws {
        // 1. Pure core
        try check(AppVersion.current.version == "0.9.0", "Version attendue 0.9.0, lue \(AppVersion.current.version)")
        let parsed = ScanRange.parseAll("192.168.1.0/30, 10.0.0.5")
        try check(parsed.firstInvalidIndex == nil && ScanRange.uniqueAddresses(parsed.ranges) == ["10.0.0.5", "192.168.1.1", "192.168.1.2"], "ScanRange.parseAll")
        try check(OUILookup.shared.isAvailable, "Base des fabricants introuvable")
        try check(OUILookup.shared.vendor(forMAC: "f0:18:98:00:00:01") == "Apple, Inc.", "OUI Apple")
        try check(OUILookup.shared.resolve("2a:91:f0:5e:66:c3").status == .localAddress, "MAC privée")
        let hosts = SyntheticScan.hosts()
        try check(DeviceClassifier.classify(hosts[1]) == .mac, "Classifieur : Mac Studio")
        try check(DeviceClassifier.classify(hosts[2]) == .phone, "Classifieur : iPhone")
        try check(DeviceClassifier.classify(hosts[3]) == .tv, "Classifieur : Apple TV")
        try check(DeviceClassifier.classify(hosts[4]) == .printer, "Classifieur : imprimante")
        try check(DeviceClassifier.classify(hosts[7]) == .speaker, "Classifieur : HomePod")
        try check(DeviceClassifier.classify(hosts[8]) == .windows, "Classifieur : Windows")
        try check(DeviceClassifier.classify(hosts[0]) == .router, "Classifieur : Freebox")
        try check(DeviceClassifier.assessment(hosts[0]).isCertain && DeviceClassifier.assessment(hosts[1]).isCertain, "Rôles passerelle et ce Mac : certitude")
        try check(DeviceClassifier.classify(hosts[10]) == .networkGear, "Classifieur : Ubiquiti")
        try check(DeviceClassifier.classify(hosts[11]) == .console, "Classifieur : Nintendo")
        try check(DeviceClassifier.classify(hosts[9]) == .iot, "Classifieur : Shelly")
        try check(DeviceClassifier.assessment(Host(ip: "10.0.0.9", vendor: "NETGEAR")).confidence == .probable, "Vendeur seul : estimation probable")

        let rows = ExportService.rows(from: hosts.filter { $0.status == .alive }) { SyntheticScan.labels[$0.mac ?? ""] }
        try check(ExportService.csv(rows: rows).split(separator: "\n").count == rows.count + 1, "CSV : une ligne par appareil")
        let json = try ExportService.json(rows: rows)
        try check(try JSONDecoder().decode([ExportService.Row].self, from: json).count == rows.count, "JSON aller-retour")
        try check(ExportService.ipPortList(rows: rows).contains("192.168.1.1:443"), "Liste IP:port")

        let data = try SnapshotIO.encode(SyntheticScan.snapshot())
        let decoded = try SnapshotIO.decode(data)
        try check(decoded.hosts.count == hosts.count && decoded.labels == SyntheticScan.labels, "Snapshot aller-retour")
        let diff = SnapshotDiff.compute(current: hosts, baseline: SyntheticScan.baseline())
        try check(diff.newCount == 1 && diff.missingCount == 1 && diff.modifiedCount == 1, "Comparaison : +1 ~1 -1, lu +\(diff.newCount) ~\(diff.modifiedCount) -\(diff.missingCount)")
        try check(SubnetCalculator.summarize("10.1.2.3/26")?.hostCount == 62, "Calculateur de sous-réseau")
        try check(NetBIOSResolver.buildQuery(transactionID: 1).count == 50, "Requête NetBIOS")
        try check(WakeOnLAN.magicPacket(mac: "f0:18:98:4c:2a:7d")?.count == 102, "Paquet magique")
        try check(PortScanner.parsePorts("22, 80, 8000-8002") == [22, 80, 8000, 8001, 8002], "Analyse de ports")

        // 2. Engine on loopback
        try check(ICMPPinger.shared != nil, "Socket ICMP refusé")
        let ping = await NetworkScanner.ping("127.0.0.1", timeout: .seconds(2))
        try check(ping != nil && ping!.ttl == 64, "Ping loopback")
        let sweep = await ICMPPinger.shared!.sweep([IPv4.uint32(from: "127.0.0.1")!], replyTimeout: .milliseconds(500), onReply: { _ in })
        try check(sweep.sent == 1 && sweep.replies == 1 && sweep.rejected == 0, "Compte-rendu du balayage : \(sweep)")
        var sawAlive = false, sawDone = false
        for await event in NetworkScanner(profile: .quick).scan(addresses: ["127.0.0.1"]) {
            if case .host(let h) = event, h.ip == "127.0.0.1", h.status == .alive { sawAlive = true }
            if case .done = event { sawDone = true }
        }
        try check(sawAlive && sawDone, "Pipeline de découverte sur loopback")

        // 3. Controller lifecycle with an injected stream
        var operations = ScanController.Operations()
        operations.scan = { addresses, _ in
            AsyncStream { continuation in
                for ip in addresses { continuation.yield(.host(Host(ip: ip, status: .alive))) }
                continuation.yield(.progress(scanned: addresses.count, total: addresses.count))
                continuation.yield(.done)
                continuation.finish()
            }
        }
        let controller = ScanController(operations: operations)
        controller.rangeInput = "10.9.9.1-10.9.9.3"
        controller.profile = .quick
        controller.start()
        let deadline = Date().addingTimeInterval(3)
        while controller.isScanning, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        try check(controller.state == .done(scanned: 3, total: 3) && controller.aliveCount == 3, "Cycle du contrôleur")
        controller.searchQuery = "9.2"
        try check(controller.filteredHosts.map(\.ip) == ["10.9.9.2"], "Recherche")
        controller.stop()

        // 4. The window
        let model = AppModel(startServices: false)
        SyntheticScan.load(into: model)
        try check(model.inspectedHost?.ip == "192.168.1.12", "Sélection de la fiche")
        try check(model.visibleHosts.count == 12, "Lignes visibles : 12, lu \(model.visibleHosts.count)")
        model.sortKey = .latency
        try check(model.visibleHosts.first?.ip == "192.168.1.12", "Tri par latence")
        model.sortKey = .ip
        try check(model.scan.diff?.newCount == 1, "Comparaison chargée")
        let png = Snapshot.renderOffscreenPNG(model: model)
        try check((png?.count ?? 0) > 20_000, "Rendu de la fenêtre")
        try check(model.statusMessage.contains("12 appareils"), "Message d'état : \(model.statusMessage)")
    }
}
