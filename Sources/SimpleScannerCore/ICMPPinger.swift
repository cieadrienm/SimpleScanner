import Darwin
import Foundation

/// Echo requests over one ICMP datagram socket, which macOS grants without privileges.
/// Replies are matched by sequence number and source address; the IPv4 header that macOS
/// prepends to every datagram gives the TTL. One receiver thread serves every sweep and ping.
public final class ICMPPinger: @unchecked Sendable {
    public struct Reply: Sendable, Hashable {
        public let address: UInt32
        public let rttMs: Double
        public let ttl: Int
    }

    public struct SweepReport: Sendable {
        public var sent = 0
        /// Addresses the kernel refused outright (`EHOSTUNREACH`): a neighbour whose ARP probe failed
        /// in the last 20 s, or macOS denying the app access to the local network.
        public var rejected = 0
        public var failed = 0
        public var replies = 0
        public init() {}
    }

    public enum PingerError: Error, CustomStringConvertible {
        case socket(Int32)
        public var description: String { if case .socket(let e) = self { return String(cString: strerror(e)) } ; return "" }
    }

    /// The app-wide pinger; nil when the kernel refuses an ICMP socket.
    public static let shared: ICMPPinger? = try? ICMPPinger()

    private let fd: Int32
    private let ident: UInt16
    private let lock = NSLock()
    private var nextSequence = UInt16.random(in: 0...UInt16.max)
    private var inFlight: [UInt16: Pending] = [:]
    private var listeners: [UUID: @Sendable (Reply) -> Void] = [:]
    private var replyCounts: [UUID: Int] = [:]

    private struct Pending {
        let address: UInt32
        let sentAt: UInt64
        let owner: UUID
    }

    public init() throws {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { throw PingerError.socket(errno) }
        var size: Int32 = 1 << 20
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        ident = UInt16(truncatingIfNeeded: getpid()) ^ UInt16.random(in: 0...0x0FFF)
        let thread = Thread { [self] in receiveLoop() }
        thread.name = "simplescanner.icmp"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: - Sweep

    /// Sends one echo to each address, paced so the kernel's ARP queue keeps up, then listens for
    /// `replyTimeout` after the last send. Replies arrive on the receiver thread as they come.
    public func sweep(
        _ addresses: [UInt32],
        replyTimeout: Duration = .seconds(1),
        paceMicroseconds: UInt32? = nil,
        onReply: @escaping @Sendable (Reply) -> Void,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> SweepReport {
        var report = SweepReport()
        guard !addresses.isEmpty else { return report }
        let owner = UUID()
        lock.withLock { listeners[owner] = onReply; replyCounts[owner] = 0 }
        func finish() -> SweepReport {
            report.replies = lock.withLock {
                listeners.removeValue(forKey: owner)
                inFlight = inFlight.filter { $0.value.owner != owner }
                return replyCounts.removeValue(forKey: owner) ?? 0
            }
            return report
        }
        // 1.5 ms between echoes keeps a /24 under half a second; larger ranges tighten the pace.
        let pace = paceMicroseconds ?? (addresses.count <= 1024 ? 1500 : UInt32(max(300, 1_500_000 / addresses.count)))
        for (index, address) in addresses.enumerated() {
            if Task.isCancelled { return finish() }
            switch await send(to: address, owner: owner) {
            case .sent: report.sent += 1
            case .rejected: report.rejected += 1
            case .failed: report.failed += 1
            }
            if index % 16 == 15 { onProgress?(index + 1) }
            try? await Task.sleep(for: .microseconds(Int64(pace)))
        }
        onProgress?(addresses.count)
        let deadline = ContinuousClock.now + replyTimeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return finish()
    }

    /// One echo, one reply or nil after `timeout`.
    public func ping(_ address: UInt32, timeout: Duration = .seconds(1)) async -> Reply? {
        let owner = UUID()
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Reply?, Never>) in
            lock.withLock {
                listeners[owner] = { reply in once.fire { continuation.resume(returning: reply) } }
            }
            Task {
                let outcome = await self.send(to: address, owner: owner)
                if outcome != .sent { once.fire { continuation.resume(returning: nil) } }
                try? await Task.sleep(for: timeout)
                once.fire { continuation.resume(returning: nil) }
                self.lock.withLock {
                    self.listeners.removeValue(forKey: owner)
                    self.inFlight = self.inFlight.filter { $0.value.owner != owner }
                }
            }
        }
    }

    // MARK: - Wire

    private enum SendOutcome: Equatable { case sent, rejected, failed }

    private func send(to address: UInt32, owner: UUID) async -> SendOutcome {
        let sequence: UInt16 = lock.withLock {
            let value = nextSequence
            nextSequence &+= 1
            return value
        }
        var packet = [UInt8](repeating: 0, count: 8 + 16)
        packet[0] = 8 // echo request
        packet[4] = UInt8(ident >> 8); packet[5] = UInt8(ident & 0xff)
        packet[6] = UInt8(sequence >> 8); packet[7] = UInt8(sequence & 0xff)
        let sentAt = Self.now()
        for i in 0..<8 { packet[8 + i] = UInt8((sentAt >> (8 * UInt64(7 - i))) & 0xff) }
        for i in 0..<4 { packet[16 + i] = UInt8((address >> (8 * UInt32(3 - i))) & 0xff) }
        let sum = Self.checksum(packet)
        packet[2] = UInt8(sum >> 8); packet[3] = UInt8(sum & 0xff)

        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = address.bigEndian

        lock.withLock { inFlight[sequence] = Pending(address: address, sentAt: sentAt, owner: owner) }
        var attempts = 0
        while true {
            let sent = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &sin) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent >= 0 { return .sent }
            let error = errno
            if (error == EAGAIN || error == ENOBUFS), attempts < 100 {
                attempts += 1
                try? await Task.sleep(for: .milliseconds(2))
                continue
            }
            lock.withLock { _ = inFlight.removeValue(forKey: sequence) }
            return (error == EHOSTUNREACH || error == EHOSTDOWN || error == ENETUNREACH) ? .rejected : .failed
        }
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            while true {
                fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &from) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &buffer, buffer.count, MSG_DONTWAIT, $0, &fromLength)
                    }
                }
                if count <= 0 { break }
                let received = Self.now()
                var offset = 0
                var ttl = 64
                if count >= 20, buffer[0] >> 4 == 4 {
                    offset = Int(buffer[0] & 0x0f) * 4
                    ttl = Int(buffer[8])
                }
                guard count >= offset + 16, buffer[offset] == 0 else { continue } // echo reply only
                let replyIdent = UInt16(buffer[offset + 4]) << 8 | UInt16(buffer[offset + 5])
                guard replyIdent == ident else { continue }
                let sequence = UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
                let source = UInt32(bigEndian: from.sin_addr.s_addr)
                var sentAt: UInt64 = 0
                for i in 0..<8 { sentAt = sentAt << 8 | UInt64(buffer[offset + 8 + i]) }

                lock.lock()
                guard let pending = inFlight[sequence], pending.address == source else { lock.unlock(); continue }
                inFlight.removeValue(forKey: sequence)
                let listener = listeners[pending.owner]
                replyCounts[pending.owner, default: 0] += 1
                lock.unlock()
                let origin = (sentAt > 0 && sentAt <= received) ? sentAt : pending.sentAt
                listener?(Reply(address: source, rttMs: Double(received &- origin) / 1_000_000, ttl: ttl))
            }
        }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }

    private static func now() -> UInt64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
    }
}
