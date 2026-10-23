import Foundation
import Darwin

public enum DNSResolver {
    private static let queue = DispatchQueue(label: "simplescanner.dns", qos: .utility, attributes: .concurrent)

    /// Reverse lookup through the system resolver (which answers `.local` names via mDNSResponder),
    /// raced against a timeout. `getnameinfo` cannot be cancelled, so a slow lookup finishes on its own
    /// and its result is discarded.
    public static func reverseLookup(_ ip: String, timeout: Duration = .seconds(1)) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let state = ResumeOnce()
            Task {
                let result = await rawLookup(ip)
                state.fire { continuation.resume(returning: result) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                state.fire { continuation.resume(returning: nil) }
            }
        }
    }

    private static func rawLookup(_ ip: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                var sin = sockaddr_in()
                sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                sin.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ip, &sin.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }
                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &sin) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        getnameinfo(sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size), &hostBuf, socklen_t(NI_MAXHOST), nil, 0, NI_NAMEREQD)
                    }
                }
                if rc == 0 {
                    let host = String(cString: hostBuf)
                    continuation.resume(returning: host.isEmpty ? nil : host)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
