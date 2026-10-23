import AppKit
import Foundation
import Observation
import SimpleScannerCore
import UniformTypeIdentifiers

/// What the window shows besides the scan: panels, sheets, sorting, and the file actions.
@MainActor
@Observable
final class AppModel {
    enum SortKey: String, CaseIterable {
        case ip, name, vendor, mac, ports, latency
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv, json, ipPort, text
        var id: String { rawValue }
        var label: String {
            switch self {
            case .csv: "CSV"
            case .json: "JSON"
            case .ipPort: "Liste IP:port"
            case .text: "Rapport texte"
            }
        }
        var fileExtension: String {
            switch self {
            case .csv: "csv"
            case .json: "json"
            case .ipPort, .text: "txt"
            }
        }
        var detail: String {
            switch self {
            case .csv: "Une ligne par appareil : IP, nom, MAC, fabricant, latence, ports, état."
            case .json: "Les mêmes champs, structurés, pour vos scripts."
            case .ipPort: "Une ligne `ip:port` par port ouvert, prête pour Nmap ou un pare-feu."
            case .text: "Un tableau lisible pour un ticket ou un e-mail."
            }
        }
    }

    struct Alert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    let scan: ScanController
    let mdns = MDNSDiscovery()
    let monitor = PingMonitor()

    var showSidebar: Bool { didSet { defaults.set(showSidebar, forKey: "simplescanner.sidebar") } }
    var showInspector: Bool { didSet { defaults.set(showInspector, forKey: "simplescanner.inspector") } }
    var showAbout = false
    var showHelp = false
    var showShortcuts = false
    var showExport = false
    var showPortScan = false
    var showSubnetCalculator = false
    var showWarnings = false
    var showDiff = false
    var renamingRange: SavedRange?
    var alert: Alert?
    var searchFocusRequest = 0
    var labelFocusRequest = 0

    var portsInput = PortScanner.defaultPortsInput
    var fetchBanners = true
    var portScanTargets: Set<Host.ID> = []
    var exportFormat: ExportFormat = .csv
    var exportVisibleOnly = true
    var subnetInput = ""
    var statusFlash: String?

    var sortKey: SortKey = .ip { didSet { applySort() } }
    var sortAscending = true { didSet { applySort() } }

    var defaultProfile: ScanProfile {
        didSet { defaults.set(defaultProfile.rawValue, forKey: "simplescanner.profile"); if !scan.isScanning { scan.profile = defaultProfile } }
    }
    var rescanInterval: RescanInterval {
        didSet { defaults.set(rescanInterval.rawValue, forKey: "simplescanner.rescan"); scan.rescanInterval = rescanInterval }
    }
    var showDeadHosts: Bool {
        didSet { defaults.set(showDeadHosts, forKey: "simplescanner.showDead"); scan.showDeadHosts = showDeadHosts }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var bonjourSyncScheduled = false

    init(scan: ScanController? = nil, defaults: UserDefaults = .standard, startServices: Bool = true) {
        let scan = scan ?? ScanController()
        self.scan = scan
        self.defaults = defaults
        showSidebar = defaults.object(forKey: "simplescanner.sidebar") as? Bool ?? true
        showInspector = defaults.object(forKey: "simplescanner.inspector") as? Bool ?? true
        defaultProfile = ScanProfile(rawValue: defaults.string(forKey: "simplescanner.profile") ?? "") ?? .standard
        rescanInterval = RescanInterval(rawValue: defaults.string(forKey: "simplescanner.rescan") ?? "") ?? .off
        showDeadHosts = defaults.bool(forKey: "simplescanner.showDead")
        scan.profile = defaultProfile
        scan.rescanInterval = rescanInterval
        scan.showDeadHosts = showDeadHosts
        if startServices {
            scan.detectDefaultSubnetIfNeeded()
            mdns.start()
            observeBonjour()
            Task.detached(priority: .utility) { _ = OUILookup.shared.isAvailable } // warm the vendor index off the main thread
        }
    }

    // MARK: - Derived

    var inspectedHost: Host? {
        guard scan.selection.count == 1, let id = scan.selection.first else { return nil }
        return scan.host(forID: id)
    }

    var currentInterface: NetworkInterfaceInfo? {
        let range = scan.rangeInput.trimmingCharacters(in: .whitespaces)
        return NetworkInterface.scannableInterfaces().first { $0.cidr == range }
    }

    var visibleHosts: [Host] { scan.filteredHosts }

    var statusMessage: String {
        if let statusFlash { return statusFlash }
        if let error = scan.lastError { return error }
        switch scan.state {
        case .idle:
            return scan.rangeInput.isEmpty ? "Choisissez un réseau à explorer" : "Prêt à scanner \(scan.rangeInput)"
        case .scanning(let scanned, let total):
            if scan.portScanInProgress {
                return "\(scan.phase.rawValue) · \(scan.portScanProgress.scanned)/\(scan.portScanProgress.total)"
            }
            return scan.phase == .discovery ? "\(scan.phase.rawValue) · \(scanned)/\(total)" : scan.phase.rawValue
        case .done:
            let count = scan.aliveCount
            let duration = scan.lastDuration.map { " en \(Format.elapsed($0))" } ?? ""
            if scan.snapshotURL != nil { return "Scan ouvert : \(Format.count(count, "appareil"))" }
            return count == 0 ? "Aucun appareil n'a répondu" : "\(Format.count(count, "appareil")) trouvé\(count > 1 ? "s" : "")\(duration)"
        case .stopped:
            return "Scan arrêté · \(Format.count(scan.aliveCount, "appareil"))"
        }
    }

    var isIndeterminate: Bool { scan.phase != .discovery || scan.portScanInProgress }

    // MARK: - Scan control

    func toggleScan() {
        if scan.isScanning { scan.stop() } else if scan.canStart { startScan() }
    }

    func startScan() {
        scan.profile = defaultProfile
        scan.start()
        if let error = scan.lastError { flash(error, isError: true) }
    }

    func useInterface(_ info: NetworkInterfaceInfo) {
        guard !scan.isScanning else { return }
        scan.clearImportedFile()
        scan.rangeInput = info.cidr
    }

    func setRange(_ text: String) {
        guard !scan.isScanning else { return }
        scan.clearImportedFile()
        scan.rangeInput = text.trimmingCharacters(in: .whitespaces)
        scan.reportError(nil)
    }

    func flash(_ message: String, isError: Bool = false, seconds: Double = 3) {
        statusFlash = message
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            statusFlash = nil
        }
    }

    private func applySort() {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortKey {
        case .ip: scan.sortOrder = [KeyPathComparator(\Host.ipNumeric, order: order)]
        case .name: scan.sortOrder = [KeyPathComparator(\Host.sortName, order: order), KeyPathComparator(\Host.ipNumeric)]
        case .vendor: scan.sortOrder = [KeyPathComparator(\Host.sortVendor, order: order), KeyPathComparator(\Host.ipNumeric)]
        case .mac: scan.sortOrder = [KeyPathComparator(\Host.sortMAC, order: order), KeyPathComparator(\Host.ipNumeric)]
        case .ports: scan.sortOrder = [KeyPathComparator(\Host.openPorts.count, order: order == .forward ? .reverse : .forward), KeyPathComparator(\Host.ipNumeric)]
        case .latency: scan.sortOrder = [KeyPathComparator(\Host.sortLatency, order: order), KeyPathComparator(\Host.ipNumeric)]
        }
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key { sortAscending.toggle() } else { sortKey = key; sortAscending = true }
    }

    // MARK: - Bonjour

    private func observeBonjour() {
        withObservationTracking {
            _ = mdns.servicesByIP
            _ = mdns.deviceInfoModels
            _ = scan.hosts.count
            _ = scan.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncBonjour()
                self.observeBonjour()
            }
        }
    }

    func syncBonjour() {
        scan.applyBonjour { [mdns] host in mdns.info(for: host) }
    }

    // MARK: - Selection actions

    func selectAll() {
        scan.selection = Set(visibleHosts.map(\.id))
    }

    func copySelectedIPs() {
        let ips = visibleHosts.filter { scan.selection.contains($0.id) }.map(\.ip)
        guard !ips.isEmpty else { return }
        HostActions.copy(ips.joined(separator: "\n"))
        flash(ips.count == 1 ? "Adresse \(ips[0]) copiée" : "\(ips.count) adresses copiées")
    }

    func copy(_ text: String, what: String) {
        HostActions.copy(text)
        flash("\(what) copié\(what.hasSuffix("e") ? "e" : "")")
    }

    func deleteSelected() {
        let ids = scan.selection
        guard !ids.isEmpty else { return }
        scan.deleteHosts(ids)
        flash(Format.count(ids.count, "appareil retiré", "appareils retirés") + " de la liste")
    }

    func refreshSelected() {
        guard !scan.isScanning else { return }
        let ids = scan.selection
        for id in ids { Task { await scan.refreshHost(id) } }
    }

    func wakeSelected() {
        let ids = scan.selection
        Task { await scan.runWakeOnLAN(for: ids) }
    }

    func beginPortScan(ids: Set<Host.ID>? = nil) {
        let targets = ids ?? scan.selection
        guard !targets.isEmpty, !scan.isScanning else { return }
        portScanTargets = targets
        showPortScan = true
    }

    func startPortScan() -> Bool {
        guard let ports = PortScanner.parsePorts(portsInput) else { return false }
        showPortScan = false
        scan.runPortScan(ports: ports, fetchBanners: fetchBanners, targetIds: portScanTargets)
        return true
    }

    func setLabel(_ value: String, for host: Host) {
        scan.setLabel(value, for: scan.host(forID: host.id) ?? host)
    }

    func open(service displayType: String, of host: Host) {
        let port = mdns.services(for: host.ip).first { $0.displayType == displayType }?.port
        guard let action = HostActions.action(forService: displayType, port: port) else { return }
        HostActions.open(action.connection, ip: host.ip, port: action.port)
    }

    func open(port: Int, of host: Host) {
        guard let action = HostActions.action(forPort: port) else { return }
        HostActions.open(action.connection, ip: host.ip, port: action.port)
    }

    func toggleInspector() {
        showInspector.toggle()
    }

    func revealInspector() {
        if !showInspector { showInspector = true }
    }

    // MARK: - Files

    func openSnapshotPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: ScanSnapshot.fileExtension) ?? .json, .json]
        panel.message = "Ouvrir un scan enregistré (.simplescan ou .ipscan.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try SnapshotIO.decode(data)
            scan.applySnapshot(snapshot, from: url)
            syncBonjour()
            flash("Scan du \(Self.dateFormatter.string(from: snapshot.createdAt)) ouvert")
        } catch {
            alert = Alert(title: "Ouverture impossible", message: error.localizedDescription)
        }
    }

    func saveSnapshotPanel() {
        guard !scan.hosts.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ScanSnapshot.fileExtension) ?? .json]
        panel.nameFieldStringValue = SnapshotIO.defaultFileName()
        panel.message = "Enregistrer ce scan pour le rouvrir ou le comparer plus tard"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SnapshotIO.encode(scan.makeSnapshot()).write(to: url, options: .atomic)
            flash("Scan enregistré : \(url.lastPathComponent)")
        } catch {
            alert = Alert(title: "Enregistrement impossible", message: error.localizedDescription)
        }
    }

    func compareSnapshotPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: ScanSnapshot.fileExtension) ?? .json, .json]
        panel.message = "Choisir le scan de référence : les nouveautés, changements et disparitions seront marqués"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let snapshot = try SnapshotIO.decode(try Data(contentsOf: url))
            scan.loadComparisonBaseline(snapshot)
            flash("Comparaison avec le scan du \(Self.dateFormatter.string(from: snapshot.createdAt))")
        } catch {
            alert = Alert(title: "Comparaison impossible", message: error.localizedDescription)
        }
    }

    func importTargetsPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .text]
        panel.message = "Un fichier .txt ou .csv : une adresse, un CIDR ou une plage par ligne (virgules acceptées)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try scan.loadImportedFile(url: url)
            if summary.invalidLineCount > 0 {
                alert = Alert(title: "Import partiel", message: "\(summary.targetCount) cibles lues. \(summary.invalidLineCount) ligne\(summary.invalidLineCount > 1 ? "s" : "") illisible\(summary.invalidLineCount > 1 ? "s" : "") ignorée\(summary.invalidLineCount > 1 ? "s" : "").")
            } else {
                flash("\(Format.count(summary.targetCount, "cible")) importée\(summary.targetCount > 1 ? "s" : "")")
            }
        } catch {
            alert = Alert(title: "Import impossible", message: error.localizedDescription)
        }
    }

    func exportRows(visibleOnly: Bool) -> [ExportService.Row] {
        let hosts = visibleOnly ? visibleHosts : scan.hosts.filter { $0.status == .alive }
        return ExportService.rows(from: hosts) { [scan] in scan.label(for: $0) }
    }

    func exportText(format: ExportFormat, visibleOnly: Bool) throws -> String {
        let rows = exportRows(visibleOnly: visibleOnly)
        switch format {
        case .csv: return ExportService.csv(rows: rows)
        case .json: return String(decoding: try ExportService.json(rows: rows), as: UTF8.self)
        case .ipPort: return ExportService.ipPortList(rows: rows)
        case .text:
            let total: Int
            if case .done(_, let t) = scan.state { total = t } else { total = scan.hosts.count }
            return ExportService.textReport(rows: rows, rangeInput: scan.rangeInput, scannedTotal: total, aliveCount: scan.aliveCount)
        }
    }

    func copyExport() {
        do {
            HostActions.copy(try exportText(format: exportFormat, visibleOnly: exportVisibleOnly))
            showExport = false
            flash("Export \(exportFormat.label) copié")
        } catch {
            alert = Alert(title: "Export impossible", message: error.localizedDescription)
        }
    }

    func saveExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: exportFormat.fileExtension)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportText(format: exportFormat, visibleOnly: exportVisibleOnly).write(to: url, atomically: true, encoding: .utf8)
            showExport = false
            flash("Export enregistré : \(url.lastPathComponent)")
        } catch {
            alert = Alert(title: "Export impossible", message: error.localizedDescription)
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

extension Host {
    var sortName: String { (displayName ?? "\u{FFFF}").lowercased() }
    var sortVendor: String { (vendor ?? "\u{FFFF}").lowercased() }
    var sortMAC: String { mac ?? "\u{FFFF}" }
    var sortLatency: Double { rttMs ?? .greatestFiniteMagnitude }
}
