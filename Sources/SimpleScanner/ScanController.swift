import Foundation
import Observation
import SimpleScannerCore

/// The scan itself: targets, run lifecycle, results, labels, favourites, filters and comparison.
/// The window shows this object; the headless `--scan` mode and the tests drive it the same way.
@Observable
@MainActor
final class ScanController {
    enum State: Equatable {
        case idle
        case scanning(scanned: Int, total: Int)
        case done(scanned: Int, total: Int)
        case stopped(scanned: Int, total: Int)
    }

    static let portScanHostConcurrency = 6
    nonisolated static let maxTargets = 65_536

    // Injectable operations keep lifecycle tests independent of the local network.
    struct Operations {
        var scan: @MainActor ([String], ScanProfile) -> AsyncStream<ScanEvent> = {
            NetworkScanner(profile: $1).scan(addresses: $0)
        }
        var probe: @Sendable (String, [Int]) async -> [Int] = {
            await PortScanner.probe($0, ports: $1)
        }
        var banner: @Sendable (String, [Int]) async -> String? = {
            await BannerProbe.fetch($0, openPorts: $1)
        }
    }
    private let operations: Operations
    private var generation = UUID()
    private(set) var phase = ScanPhase.discovery

    var canStart: Bool {
        !isScanning && (importedTargets != nil || !rangeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    struct ImportedTargets {
        let url: URL
        let targets: [String]
        let invalidLineCount: Int
    }

    var rangeInput: String = ""
    var searchQuery: String = ""
    var profile: ScanProfile = .standard
    private(set) var importedTargets: ImportedTargets?
    var rescanInterval: RescanInterval = .off {
        didSet { handleRescanIntervalChange() }
    }
    var selection: Set<Host.ID> = []
    var sortOrder: [KeyPathComparator<Host>] = [KeyPathComparator(\Host.ipNumeric, order: .forward)]
    var labels: [String: String] = [:]   // anchor → label (anchor = MAC ?? IP)
    var savedRanges: [SavedRange] = []
    var showDeadHosts: Bool = false
    var filterHasOpenPorts: Bool = false
    var filterHasLabel: Bool = false
    var filterHasVendor: Bool = false
    var filterIdentifiedDevice: Bool = false
    /// Bonjour family chosen in the sidebar, e.g. `AirPlay`.
    var filterService: String?

    var hasActiveScopeFilters: Bool {
        filterHasOpenPorts || filterHasLabel || filterHasVendor || filterIdentifiedDevice || filterService != nil
    }

    var activeFilterNames: [String] {
        var names: [String] = []
        if filterHasOpenPorts { names.append(L("Ports ouverts", "Open ports")) }
        if filterHasLabel { names.append(L("Nommés", "Named")) }
        if filterHasVendor { names.append(L("Fabricant connu", "Known vendor")) }
        if filterIdentifiedDevice { names.append(L("Type identifié", "Identified type")) }
        if let filterService { names.append(MDNSDiscovery.displayService(filterService)) }
        return names
    }

    // Dead probes are collected too; their presence does not mean a device was found.
    var hasResultConstraints: Bool { hasActiveScopeFilters || !searchQuery.isEmpty }
    var showsDiscoveryEmptyState: Bool {
        filteredHosts.isEmpty && !hasResultConstraints && aliveCount == 0
    }

    func clearScopeFilters() {
        filterHasOpenPorts = false
        filterHasLabel = false
        filterHasVendor = false
        filterIdentifiedDevice = false
        filterService = nil
    }

    private(set) var hosts: [Host] = []
    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastDuration: TimeInterval?
    private(set) var lastError: String?
    private(set) var portScanInProgress: Bool = false
    private(set) var portScanProgress: (scanned: Int, total: Int) = (0, 0)
    private(set) var warnings: [ScanWarning] = []
    private(set) var lastSweep: (sent: Int, replies: Int, rejected: Int)?
    private(set) var diff: SnapshotDiff?
    private(set) var snapshotURL: URL?
    private var diffBaseline: ScanSnapshot?
    private var portScanTask: Task<Void, Never>?

    init(operations: Operations = Operations()) {
        self.operations = operations
        self.labels = PersistedStore.loadLabels()
        self.savedRanges = PersistedStore.loadRanges().sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var indexByIP: [String: Int] = [:]
    private var scanTask: Task<Void, Never>?
    private var startDate: Date?
    private var elapsedTimer: Timer?
    private var rescanTimer: Timer?
    private(set) var nextRescanAt: Date?

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var progressFraction: Double {
        if portScanInProgress, portScanProgress.total > 0 {
            return Double(portScanProgress.scanned) / Double(portScanProgress.total)
        }
        if case .scanning(let scanned, let total) = state, total > 0 { return Double(scanned) / Double(total) }
        return 0
    }

    var aliveCount: Int { hosts.reduce(0) { $0 + ($1.status == .alive ? 1 : 0) } }
    var aliveHosts: [Host] { hosts.filter { $0.status == .alive } }

    var filteredHosts: [Host] {
        var visible = showDeadHosts ? hosts : hosts.filter { $0.status != .dead }
        if filterHasOpenPorts { visible = visible.filter { !$0.openPorts.isEmpty } }
        if filterHasLabel { visible = visible.filter { label(for: $0) != nil } }
        if filterHasVendor { visible = visible.filter { ($0.vendor?.isEmpty == false) } }
        if filterIdentifiedDevice { visible = visible.filter { DeviceClassifier.classify($0) != .unknown } }
        if let filterService {
            let target = MDNSDiscovery.displayService(filterService)
            visible = visible.filter { $0.services.contains(filterService) || $0.services.map(MDNSDiscovery.displayService).contains(target) }
        }
        let rows: [Host]
        if searchQuery.isEmpty {
            rows = visible
        } else {
            let q = searchQuery.lowercased()
            rows = visible.filter { h in
                h.ip.lowercased().contains(q)
                    || (h.hostname?.lowercased().contains(q) ?? false)
                    || (h.netbiosName?.lowercased().contains(q) ?? false)
                    || (h.bonjourName?.lowercased().contains(q) ?? false)
                    || (h.mac?.lowercased().contains(q) ?? false)
                    || (h.vendor?.lowercased().contains(q) ?? false)
                    || (h.model?.lowercased().contains(q) ?? false)
                    || (h.serviceTitle?.lowercased().contains(q) ?? false)
                    || h.services.contains(where: { $0.lowercased().contains(q) })
                    || (label(for: h)?.lowercased().contains(q) ?? false)
            }
        }
        return rows.sorted(using: sortOrder)
    }

    func host(forID id: Host.ID) -> Host? { hosts.first { $0.id == id } }
    func host(forIP ip: String) -> Host? { indexByIP[ip].map { hosts[$0] } }
    var selectedHosts: [Host] { hosts.filter { selection.contains($0.id) } }

    // MARK: - Labels

    func anchor(for host: Host) -> String { MACAddress.anchor(mac: host.mac, ip: host.ip) }
    func label(for host: Host) -> String? { MACAddress.label(in: labels, mac: host.mac, ip: host.ip) }

    /// The row title: the user's label, else the device's own name, else nothing.
    func title(for host: Host) -> String? { label(for: host) ?? host.displayName }

    func setLabel(_ value: String?, for host: Host) {
        let key = anchor(for: host)
        if let mac = host.mac, let address = MACAddress(mac) {
            for oldKey in labels.keys.filter({ MACAddress($0) == address }) { labels.removeValue(forKey: oldKey) }
        }
        // Retire an IP fallback after enrichment supplies the stable MAC anchor.
        labels.removeValue(forKey: host.ip)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { labels[key] = trimmed } else { labels.removeValue(forKey: key) }
        PersistedStore.saveLabels(labels)
    }

    // MARK: - Saved ranges

    var isCurrentRangeSaved: Bool {
        let key = rangeInput.trimmingCharacters(in: .whitespaces)
        return !key.isEmpty && savedRanges.contains { $0.range == key }
    }

    func toggleSaveCurrentRange() {
        let key = rangeInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if let idx = savedRanges.firstIndex(where: { $0.range == key }) {
            savedRanges.remove(at: idx)
        } else {
            savedRanges.append(SavedRange(range: key, name: nil))
            sortSavedRanges()
        }
        PersistedStore.saveRanges(savedRanges)
    }

    func removeSavedRange(_ range: String) {
        savedRanges.removeAll { $0.range == range }
        PersistedStore.saveRanges(savedRanges)
    }

    func renameSavedRange(_ range: String, to name: String?) {
        guard let idx = savedRanges.firstIndex(where: { $0.range == range }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        savedRanges[idx].name = (trimmed?.isEmpty == false) ? trimmed : nil
        sortSavedRanges()
        PersistedStore.saveRanges(savedRanges)
    }

    func loadSavedRange(_ range: String) {
        guard !isScanning else { return }
        clearImportedFile()
        rangeInput = range
    }

    private func sortSavedRanges() {
        savedRanges.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    func detectDefaultSubnetIfNeeded() {
        guard rangeInput.isEmpty, importedTargets == nil else { return }
        if let subnet = NetworkInterface.defaultSubnet() { rangeInput = subnet }
    }

    // MARK: - Imported targets (file)

    struct ImportSummary {
        let targetCount: Int
        let invalidLineCount: Int
    }

    @discardableResult
    func loadImportedFile(url: URL) throws -> ImportSummary {
        let result = try TargetFileParser.parse(url: url)
        if result.targets.isEmpty { throw TargetFileParser.ParseError.noTargets }
        importedTargets = ImportedTargets(url: url, targets: result.targets, invalidLineCount: result.invalidLines.count)
        lastError = nil
        return ImportSummary(targetCount: result.targets.count, invalidLineCount: result.invalidLines.count)
    }

    func clearImportedFile() { importedTargets = nil }

    // MARK: - Run lifecycle

    struct TargetError: Error, CustomStringConvertible {
        let description: String
    }

    /// The addresses a scan would cover now, or an error message.
    func resolveTargets() -> Result<[String], TargetError> {
        if let imported = importedTargets { return .success(imported.targets) }
        let parsed = ScanRange.parseAll(rangeInput)
        if let badIdx = parsed.firstInvalidIndex {
            return .failure(TargetError(description: L("Plage invalide (élément \(badIdx)). Exemples : 10.0.0.0/24, 192.168.1.50-192.168.1.100", "Invalid range (item \(badIdx)). Examples: 10.0.0.0/24, 192.168.1.50-192.168.1.100")))
        }
        guard !parsed.ranges.isEmpty else { return .failure(TargetError(description: L("Saisir une plage d'adresses (par ex. 192.168.1.0/24).", "Enter an address range (e.g. 192.168.1.0/24)."))) }
        let totalHosts = ScanRange.totalHostCount(parsed.ranges)
        if totalHosts > Self.maxTargets {
            return .failure(TargetError(description: L("Plage trop grande (\(totalHosts) adresses). Réduisez-la ou scindez-la.", "Range too large (\(totalHosts) addresses). Narrow or split it.")))
        }
        let addresses = ScanRange.uniqueAddresses(parsed.ranges)
        guard !addresses.isEmpty else { return .failure(TargetError(description: L("Aucune adresse à sonder.", "No address to probe."))) }
        return .success(addresses)
    }

    func start() {
        guard !isScanning else { return }
        let addresses: [String]
        switch resolveTargets() {
        case .success(let list): addresses = list
        case .failure(let error): lastError = error.description; return
        }
        if addresses.count > Self.maxTargets {
            lastError = L("Liste trop grande (\(addresses.count) adresses). Réduisez-la ou scindez-la.", "List too large (\(addresses.count) addresses). Narrow or split it.")
            return
        }

        stop()
        generation = UUID()
        let runID = generation
        phase = .discovery
        selection = []
        lastError = nil
        hosts = []
        indexByIP = [:]
        warnings = []
        diff = nil
        snapshotURL = nil
        cancelRescanTimer()
        startDate = Date()
        elapsed = 0
        lastDuration = nil
        state = .scanning(scanned: 0, total: addresses.count)

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }

        let runProfile = profile
        let events = operations.scan(addresses, runProfile)
        scanTask = Task { [weak self] in
            for await event in events {
                guard let self, self.generation == runID, !Task.isCancelled else { return }
                self.handle(event: event)
            }
            guard let self, self.generation == runID, !Task.isCancelled else { return }
            if runProfile.autoPortScan {
                let targets = self.hosts.filter { $0.status == .alive }
                self.portScanInProgress = true
                self.portScanProgress = (0, targets.count)
                await self.executePortScan(targets: targets, ports: PortScanner.commonPorts, fetchBanners: true, runID: runID)
            }
            guard self.generation == runID, !Task.isCancelled else { return }
            self.finishRun()
        }
    }

    func stop() {
        generation = UUID() // Invalidate callbacks before cancelling their producers.
        scanTask?.cancel()
        scanTask = nil
        portScanTask?.cancel()
        portScanTask = nil
        portScanInProgress = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        cancelRescanTimer()
        if case .scanning(let s, let t) = state {
            state = .stopped(scanned: s, total: t)
            lastDuration = elapsed
        }
    }

    private func finishRun() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        portScanInProgress = false
        scanTask = nil
        portScanTask = nil
        if case .scanning(let s, let t) = state { state = .done(scanned: s, total: t) }
        lastDuration = elapsed
        recomputeDiff()
        scheduleRescan()
    }

    private func handleRescanIntervalChange() {
        cancelRescanTimer()
        if case .done = state, rescanInterval.seconds != nil { scheduleRescan() }
    }

    private func scheduleRescan() {
        guard let interval = rescanInterval.seconds else { return }
        cancelRescanTimer()
        nextRescanAt = Date().addingTimeInterval(interval)
        let scheduledGeneration = generation
        rescanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == scheduledGeneration else { return }
                self.rescanTimer = nil
                self.nextRescanAt = nil
                if self.canStart { self.start() }
            }
        }
    }

    private func cancelRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = nil
        nextRescanAt = nil
    }

    // MARK: - Port scan

    func runPortScan(ports: [Int], fetchBanners: Bool = false, targetIds: Set<Host.ID>? = nil) {
        let ids = targetIds ?? selection
        let targets = hosts.filter { ids.contains($0.id) }
        guard !targets.isEmpty, !isScanning else { return }
        stop()
        generation = UUID()
        let runID = generation
        state = .scanning(scanned: hosts.count, total: hosts.count)
        startDate = Date()
        elapsed = 0
        portScanInProgress = true
        portScanProgress = (0, targets.count)
        portScanTask = Task { [weak self] in
            await self?.executePortScan(targets: targets, ports: ports, fetchBanners: fetchBanners, runID: runID)
            guard let self, self.generation == runID, !Task.isCancelled else { return }
            self.finishRun()
        }
    }

    func cancelPortScan() { stop() }

    private func executePortScan(targets: [Host], ports: [Int], fetchBanners: Bool, runID: UUID) async {
        guard generation == runID, !Task.isCancelled else { return }
        phase = .ports
        let probe = operations.probe
        let bannerProbe = operations.banner
        var completed = 0

        await withTaskGroup(of: (UUID, [Int]).self) { group in
            var iter = targets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, targets.count) {
                guard let host = iter.next() else { break }
                let ip = host.ip, id = host.id
                group.addTask { (id, await probe(ip, ports)) }
            }
            while let (id, openPorts) = await group.next() {
                if Task.isCancelled || generation != runID { group.cancelAll(); break }
                if let idx = hosts.firstIndex(where: { $0.id == id }) { hosts[idx].openPorts = openPorts }
                completed += 1
                portScanProgress = (completed, targets.count)
                if let next = iter.next() {
                    let ip = next.ip, nextId = next.id
                    group.addTask { (nextId, await probe(ip, ports)) }
                }
            }
        }

        if Task.isCancelled || generation != runID { return }
        guard fetchBanners else { return }
        phase = .banners

        let targetIds = Set(targets.map(\.id))
        let bannerTargets: [(UUID, String, [Int])] = hosts
            .filter { targetIds.contains($0.id) }
            .compactMap { h in
                let banner = h.openPorts.filter { [80, 443, 22, 8080, 8443].contains($0) }
                return banner.isEmpty ? nil : (h.id, h.ip, banner)
            }

        portScanProgress = (0, bannerTargets.count)
        var failures = 0
        await withTaskGroup(of: (UUID, String?).self) { group in
            var pending = bannerTargets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, bannerTargets.count) {
                guard let (id, ip, ports) = pending.next() else { break }
                group.addTask { (id, await bannerProbe(ip, ports)) }
            }
            for await (id, title) in group {
                if Task.isCancelled || generation != runID { group.cancelAll(); break }
                portScanProgress = (portScanProgress.scanned + 1, bannerTargets.count)
                if let (nextID, ip, ports) = pending.next() {
                    group.addTask { (nextID, await bannerProbe(ip, ports)) }
                }
                guard let title else { failures += 1; continue }
                if let idx = hosts.firstIndex(where: { $0.id == id }) { hosts[idx].serviceTitle = title }
            }
        }
        if generation == runID, !Task.isCancelled, failures > 0 {
            mergeWarning(.bannerFetchFailures(count: failures))
        }
    }

    // MARK: - Bonjour

    /// Folds what Bonjour knows into the matching rows.
    func applyBonjour(_ infoFor: (Host) -> MDNSDiscovery.DeviceInfo) {
        for idx in hosts.indices where hosts[idx].status == .alive {
            let info = infoFor(hosts[idx])
            if hosts[idx].services != info.services { hosts[idx].services = info.services }
            if let name = info.names.first, hosts[idx].bonjourName != name { hosts[idx].bonjourName = name }
            if let model = info.model, hosts[idx].model != model { hosts[idx].model = model }
        }
    }

    // MARK: - Snapshot

    func makeSnapshot() -> ScanSnapshot {
        var relevantLabels: [String: String] = [:]
        for h in hosts {
            if let label = label(for: h) { relevantLabels[anchor(for: h)] = label }
        }
        return ScanSnapshot(createdAt: Date(), rangeInput: rangeInput, hosts: hosts.map(ScanSnapshot.HostRecord.init), labels: relevantLabels)
    }

    func reportError(_ message: String?) { lastError = message }

    // MARK: - Comparison / diff

    func loadComparisonBaseline(_ snapshot: ScanSnapshot) {
        diffBaseline = snapshot
        recomputeDiff()
    }

    func clearComparison() {
        diffBaseline = nil
        diff = nil
    }

    var hasComparison: Bool { diffBaseline != nil }

    func recomputeDiff() {
        guard let baseline = diffBaseline else { diff = nil; return }
        diff = SnapshotDiff.compute(current: hosts, baseline: baseline)
    }

    func change(for host: Host) -> HostChange? {
        diff?.changesByAnchor[anchor(for: host)]
    }

    func applySnapshot(_ snapshot: ScanSnapshot, from url: URL? = nil) {
        stop()
        scanTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        importedTargets = nil
        rangeInput = snapshot.rangeInput
        let restored = snapshot.hosts.map { $0.host(vendorStatus: .historical) }
        hosts = restored
        rebuildIndex()
        for (key, value) in snapshot.labels where labels[key] == nil { labels[key] = value }
        PersistedStore.saveLabels(labels)
        selection = []
        elapsed = 0
        lastDuration = nil
        startDate = nil
        warnings = []
        snapshotURL = url
        state = .done(scanned: restored.count, total: restored.count)
        lastError = nil
        recomputeDiff()
    }

    func deleteHosts(_ ids: Set<Host.ID>) {
        guard !ids.isEmpty else { return }
        hosts.removeAll { ids.contains($0.id) }
        rebuildIndex()
        selection.subtract(ids)
        recomputeDiff()
    }

    func refreshHost(_ id: Host.ID) async {
        guard let target = host(forID: id) else { return }
        let runID = generation
        let ip = target.ip
        update(ip) { $0.status = .scanning }

        let result = await NetworkScanner.discover(ip, useTCPFallback: profile.useTCPFallback)
        guard generation == runID, !Task.isCancelled, host(forIP: ip) != nil else { return }

        guard let result else {
            update(ip) {
                $0.status = .dead
                $0.rttMs = nil
                $0.ttl = nil
                $0.vendorStatus = .historical
            }
            recomputeDiff()
            return
        }

        try? await Task.sleep(for: .milliseconds(150))
        let arp = await ARPLookup.read()
        async let hostnameTask = DNSResolver.reverseLookup(ip)
        async let netbiosTask: NetBIOSResolver.Result? = profile.includeNetBIOS ? NetBIOSResolver.resolve(ip) : nil
        let hostname = await hostnameTask
        let netbios = await netbiosTask
        let mac = arp.entries[ip]
        let resolution = OUILookup.shared.resolve(mac)

        guard generation == runID, !Task.isCancelled else { return }
        update(ip) {
            $0.status = .alive
            $0.discoveredBy = result.via
            $0.rttMs = result.rttMs
            $0.ttl = result.ttl
            $0.hostname = hostname
            $0.mac = mac ?? $0.mac
            $0.vendor = resolution.vendor ?? (mac == nil ? $0.vendor : nil)
            $0.vendorStatus = mac == nil && arp.error != nil ? .queryFailed : (mac == nil ? $0.vendorStatus : resolution.status)
            $0.netbiosName = netbios?.computerName ?? $0.netbiosName
            $0.workgroup = netbios?.workgroup ?? $0.workgroup
            $0.openPorts = []
            $0.serviceTitle = nil
        }
        recomputeDiff()
    }

    func runWakeOnLAN(for ids: Set<Host.ID>) async {
        let macs = hosts.filter { ids.contains($0.id) }.compactMap { $0.mac }
        guard !macs.isEmpty else { return }
        await HostActions.wakeAll(macs: macs)
    }

    // MARK: - Internals

    private func update(_ ip: String, _ body: (inout Host) -> Void) {
        guard let idx = indexByIP[ip] else { return }
        body(&hosts[idx])
    }

    private func rebuildIndex() {
        indexByIP = [:]
        for (i, h) in hosts.enumerated() { indexByIP[h.ip] = i }
    }

    private func mergeWarning(_ w: ScanWarning) {
        switch w {
        case .bannerFetchFailures(let count):
            if let idx = warnings.firstIndex(where: { if case .bannerFetchFailures = $0 { return true } else { return false } }),
               case .bannerFetchFailures(let existing) = warnings[idx] {
                warnings[idx] = .bannerFetchFailures(count: existing + count)
            } else {
                warnings.append(.bannerFetchFailures(count: count))
            }
        default:
            if !warnings.contains(w) { warnings.append(w) }
        }
    }

    private func handle(event: ScanEvent) {
        switch event {
        case .phase(let next):
            phase = next
        case .progress(let scanned, let total):
            state = .scanning(scanned: scanned, total: total)
        case .warning(let w):
            mergeWarning(w)
        case .host(let h):
            if let idx = indexByIP[h.ip] {
                hosts[idx] = hosts[idx].merged(with: h)
            } else {
                indexByIP[h.ip] = hosts.count
                hosts.append(h)
            }
        case .sweep(let sent, let replies, let rejected, _):
            lastSweep = (sent, replies, rejected)
        case .done:
            break // The owner completes only after optional port/banner enrichment.
        }
    }
}
