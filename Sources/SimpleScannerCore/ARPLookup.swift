import Foundation
import Darwin

/// The kernel's ARP table through `/usr/sbin/arp -an` (a system binary, ~20 ms): which MAC answers for which IP.
public enum ARPLookup {
    public struct Result: Sendable {
        public var entries: [String: String] = [:]
        public var error: String?
        public init(entries: [String: String] = [:], error: String? = nil) {
            self.entries = entries
            self.error = error
        }
    }

    public static func parse(_ output: String) -> Result {
        var result = Result()
        var malformed = 0
        var ambiguous = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            if line.contains("(incomplete)") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let match = line.firstMatch(of: #/\(([0-9.]+)\)\s+at\s+(\S+)/#),
                  IPv4.uint32(from: String(match.1)) != nil,
                  let mac = MACAddress(String(match.2)) else {
                malformed += 1; continue
            }
            guard mac.kind == .universal || mac.kind == .local else { continue }
            let ip = String(match.1)
            guard !ambiguous.contains(ip) else { continue }
            if let previous = result.entries[ip], previous != mac.canonical {
                result.error = "La table ARP contient des entrées contradictoires entre interfaces ; adresses MAC indisponibles."
                result.entries.removeValue(forKey: ip)
                ambiguous.insert(ip)
            } else { result.entries[ip] = mac.canonical }
        }
        if malformed > 0 { result.error = "Certaines entrées ARP n'ont pas pu être lues (\(malformed))." }
        return result
    }

    public static func read(executable: URL = URL(fileURLWithPath: "/usr/sbin/arp"), arguments: [String] = ["-an"], timeout: Double = 3) async -> Result {
        let runner = Runner()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: runner.run(executable: executable, arguments: arguments, timeout: timeout))
                }
            }
        } onCancel: { runner.cancel("Lecture de la table ARP annulée (cancelled).") }
    }

    public static func table() async -> [String: String] { await read().entries }

    private final class Runner: @unchecked Sendable {
        private let lock = NSLock()
        private let process = Process()
        private var failure: String?
        private var finished = false

        func cancel(_ message: String) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            failure = failure ?? message
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        func run(executable: URL, arguments: [String], timeout: Double) -> Result {
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            lock.lock()
            if let failure { finished = true; lock.unlock(); return Result(error: failure) }
            do { try process.run() }
            catch { finished = true; lock.unlock(); return Result(error: "Lecture de la table ARP impossible : \(error.localizedDescription)") }
            lock.unlock()
            let deadline = DispatchWorkItem { [weak self] in self?.cancel("Lecture de la table ARP trop longue (timed out).") }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deadline.cancel()
            lock.lock(); finished = true; let error = failure; lock.unlock()
            if let error { return Result(error: error) }
            guard process.terminationStatus == 0 else { return Result(error: "Lecture de la table ARP échouée (code \(process.terminationStatus)).") }
            return ARPLookup.parse(String(decoding: data, as: UTF8.self))
        }
    }
}
