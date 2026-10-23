import Foundation

public protocol NetworkScanning: Sendable {
    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent>
}

public struct DiscoverResult: Sendable, Hashable {
    public let rttMs: Double?
    public let ttl: Int?
    public let via: Host.Discovery
    public init(rttMs: Double?, ttl: Int?, via: Host.Discovery) {
        self.rttMs = rttMs
        self.ttl = ttl
        self.via = via
    }
}

/// Discovery then enrichment, as a stream of events.
///
/// Discovery: one paced ICMP echo per address (the kernel resolves ARP for each neighbour as a side
/// effect), then the ARP table marks the neighbours that ignore ping, then a TCP probe catches routed
/// hosts that block ICMP. Enrichment: MAC → vendor, reverse DNS and NetBIOS for every live host.
public struct NetworkScanner: NetworkScanning {
    public static let enrichConcurrency = 32
    public static let tcpFallbackPorts = [445, 80, 443, 22, 3389, 62078]
    public static let tcpFallbackTimeoutMs = 500
    public static let tcpFallbackConcurrency = 48
    public static let replyTimeout: Duration = .milliseconds(1000)

    public let profile: ScanProfile

    public init(profile: ScanProfile = .standard) {
        self.profile = profile
    }

    public func scan(_ range: ScanRange) -> AsyncStream<ScanEvent> {
        scan(addresses: range.addresses)
    }

    public func scan(addresses: [String]) -> AsyncStream<ScanEvent> {
        let profile = profile
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.run(addresses: addresses, profile: profile, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pipeline

    private static func run(addresses: [String], profile: ScanProfile, continuation: AsyncStream<ScanEvent>.Continuation) async {
        let total = addresses.count
        continuation.yield(.phase(.discovery))
        continuation.yield(.progress(scanned: 0, total: total))
        let values = addresses.compactMap(IPv4.uint32)
        let localRanges = NetworkInterface.localRanges()
        let own = NetworkInterface.ownAddresses()
        func isLocal(_ value: UInt32) -> Bool { localRanges.contains { $0.contains(value) } }
        let found = FoundSet()

        func finish() {
            continuation.yield(.done)
            continuation.finish()
        }

        // 1. ICMP sweep.
        var report = ICMPPinger.SweepReport()
        if let pinger = ICMPPinger.shared {
            report = await pinger.sweep(values, replyTimeout: replyTimeout, onReply: { reply in
                let result = DiscoverResult(rttMs: reply.rttMs, ttl: reply.ttl, via: .icmp)
                guard found.insert(reply.address, result) else { return }
                continuation.yield(.host(Host(ip: IPv4.string(from: reply.address), rttMs: reply.rttMs, ttl: reply.ttl, discoveredBy: .icmp, status: .alive)))
            }, onProgress: { sent in
                continuation.yield(.progress(scanned: sent, total: total))
            })
        } else {
            continuation.yield(.warning(.icmpUnavailable))
        }
        if Task.isCancelled { finish(); return }

        // 2. ARP: every neighbour that exists answered the kernel's ARP probe, ping or not.
        let arp = await ARPLookup.read()
        if let error = arp.error { continuation.yield(.warning(.arpFailed(error))) }
        var localTargets = 0
        for value in values where isLocal(value) {
            localTargets += 1
            guard !found.contains(value) else { continue }
            let ip = IPv4.string(from: value)
            guard arp.entries[ip] != nil || own.contains(ip) else { continue }
            guard found.insert(value, DiscoverResult(rttMs: nil, ttl: nil, via: .arp)) else { continue }
            continuation.yield(.host(Host(ip: ip, mac: arp.entries[ip], discoveredBy: .arp, status: .alive)))
        }
        continuation.yield(.sweep(sent: report.sent, replies: report.replies, rejected: report.rejected, arpNeighbours: arp.entries.count))
        if localTargets > 0, report.replies == 0, report.rejected > 0, !Task.isCancelled {
            continuation.yield(.warning(.localNetworkDenied))
        }
        if arp.error == nil, arp.entries.isEmpty, found.count > 0, localTargets > 0 {
            continuation.yield(.warning(.arpEmpty))
        }
        if Task.isCancelled { finish(); return }

        // 3. TCP fallback for routed targets (and for everything when no ICMP socket exists).
        var candidates: [UInt32] = []
        if profile.useTCPFallback {
            candidates = values.filter { !found.contains($0) && (!isLocal($0) || ICMPPinger.shared == nil) }
        }
        if !candidates.isEmpty {
            var completed = 0
            continuation.yield(.progress(scanned: total - candidates.count, total: total))
            await withTaskGroup(of: (UInt32, DiscoverResult?).self) { group in
                var iterator = candidates.makeIterator()
                for _ in 0..<min(tcpFallbackConcurrency, candidates.count) {
                    guard let value = iterator.next() else { break }
                    group.addTask { (value, await tcpFallback(IPv4.string(from: value))) }
                }
                while let (value, result) = await group.next() {
                    completed += 1
                    if completed % 8 == 0 { continuation.yield(.progress(scanned: total - candidates.count + completed, total: total)) }
                    if let result, found.insert(value, result) {
                        continuation.yield(.host(Host(ip: IPv4.string(from: value), rttMs: result.rttMs, discoveredBy: .tcp, status: .alive)))
                    }
                    if Task.isCancelled { group.cancelAll(); break }
                    if let next = iterator.next() {
                        group.addTask { (next, await tcpFallback(IPv4.string(from: next))) }
                    }
                }
            }
        }
        // Dead probes are reported too, so the "all addresses" view needs no second scan.
        for value in values where !found.contains(value) {
            continuation.yield(.host(Host(ip: IPv4.string(from: value), status: .dead)))
        }
        continuation.yield(.progress(scanned: total, total: total))
        if Task.isCancelled { finish(); return }

        // 4. Enrichment: vendor, reverse DNS, NetBIOS.
        continuation.yield(.phase(.enrichment))
        let oui = OUILookup.shared
        let alive = found.snapshot()
        let includeNetBIOS = profile.includeNetBIOS
        let arpError = arp.error
        await withTaskGroup(of: Host.self) { group in
            var iterator = alive.makeIterator()
            func enqueue(_ entry: (address: UInt32, result: DiscoverResult)) {
                let ip = IPv4.string(from: entry.address)
                let mac = arp.entries[ip]
                let resolution = oui.resolve(mac)
                group.addTask {
                    async let hostname = DNSResolver.reverseLookup(ip)
                    async let netbios: NetBIOSResolver.Result? = includeNetBIOS ? NetBIOSResolver.resolve(ip) : nil
                    let resolvedHost = await hostname
                    let nb = await netbios
                    return Host(
                        ip: ip,
                        hostname: resolvedHost,
                        mac: mac,
                        vendor: resolution.vendor,
                        vendorStatus: mac == nil && arpError != nil ? .queryFailed : resolution.status,
                        rttMs: entry.result.rttMs,
                        ttl: entry.result.ttl,
                        netbiosName: nb?.computerName,
                        workgroup: nb?.workgroup,
                        discoveredBy: entry.result.via,
                        status: .alive
                    )
                }
            }
            for _ in 0..<min(enrichConcurrency, alive.count) {
                guard let entry = iterator.next() else { break }
                enqueue(entry)
            }
            while let host = await group.next() {
                continuation.yield(.host(host))
                if Task.isCancelled { group.cancelAll(); break }
                if let next = iterator.next() { enqueue(next) }
            }
        }
        finish()
    }

    // MARK: - Single host

    /// Is one address alive? ICMP first; on the local subnet ARP is the judge; elsewhere a TCP probe.
    public static func discover(_ ip: String, useTCPFallback: Bool = true) async -> DiscoverResult? {
        guard let value = IPv4.uint32(from: ip), !Task.isCancelled else { return nil }
        if let pinged = await ping(ip) { return pinged }
        guard !Task.isCancelled else { return nil }
        if NetworkInterface.localRanges().contains(where: { $0.contains(value) }) {
            if NetworkInterface.ownAddresses().contains(ip) { return DiscoverResult(rttMs: nil, ttl: nil, via: .arp) }
            try? await Task.sleep(for: .milliseconds(150))
            if await ARPLookup.table()[ip] != nil { return DiscoverResult(rttMs: nil, ttl: nil, via: .arp) }
            return useTCPFallback && ICMPPinger.shared == nil ? await tcpFallback(ip) : nil
        }
        return useTCPFallback ? await tcpFallback(ip) : nil
    }

    /// ICMP echo only (the ping monitor).
    public static func ping(_ ip: String, timeout: Duration = replyTimeout) async -> DiscoverResult? {
        guard let value = IPv4.uint32(from: ip), let pinger = ICMPPinger.shared else { return nil }
        guard let reply = await pinger.ping(value, timeout: timeout) else { return nil }
        return DiscoverResult(rttMs: reply.rttMs, ttl: reply.ttl, via: .icmp)
    }

    /// Concurrent TCP probe across fallback ports. Returns the probe duration if any port handshakes.
    static func tcpFallback(_ ip: String) async -> DiscoverResult? {
        let start = ContinuousClock.now
        let openPorts = await PortScanner.probe(ip, ports: tcpFallbackPorts, timeoutMs: tcpFallbackTimeoutMs)
        guard !openPorts.isEmpty else { return nil }
        let elapsed = start.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return DiscoverResult(rttMs: max(0, ms), ttl: nil, via: .tcp)
    }
}

/// Live addresses of one run, written from the ICMP receiver thread and the pipeline task.
private final class FoundSet: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [UInt32: DiscoverResult] = [:]

    var count: Int { lock.lock(); defer { lock.unlock() }; return results.count }

    func contains(_ value: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return results[value] != nil
    }

    /// Records a result; false when the address was already found.
    func insert(_ value: UInt32, _ result: DiscoverResult) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard results[value] == nil else { return false }
        results[value] = result
        return true
    }

    func snapshot() -> [(address: UInt32, result: DiscoverResult)] {
        lock.lock(); defer { lock.unlock() }
        return results.sorted { $0.key < $1.key }.map { (address: $0.key, result: $0.value) }
    }
}
