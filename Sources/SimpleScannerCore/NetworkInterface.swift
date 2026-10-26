import Foundation
import Darwin

public struct NetworkInterfaceInfo: Hashable, Sendable {
    public let name: String
    public let ipv4: String
    public let netmaskBits: Int

    public var cidr: String { NetworkInterface.subnet(from: self) ?? "\(ipv4)/\(netmaskBits)" }
    public var isWiFi: Bool { name == "en0" || name == "en1" }
    public var isVPN: Bool { name.hasPrefix("utun") || name.hasPrefix("ppp") }
    public var kindLabel: String { isVPN ? "VPN" : name.hasPrefix("bridge") ? L("Pont", "Bridge") : "Ethernet / Wi-Fi" }
}

public enum NetworkInterface {
    public static func activeInterfaces() -> [NetworkInterfaceInfo] {
        var results: [NetworkInterfaceInfo] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return results }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let entry = ptr.pointee
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addrPtr = entry.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = String(cString: entry.ifa_name)
            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size), &hostBuf, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let ipv4 = String(cString: hostBuf)
            if ipv4.hasPrefix("169.254.") { continue }

            guard let maskPtr = entry.ifa_netmask else { continue }
            let maskBE = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bits = UInt32(bigEndian: maskBE).nonzeroBitCount
            results.append(NetworkInterfaceInfo(name: name, ipv4: ipv4, netmaskBits: bits))
        }
        return results
    }

    public static func defaultSubnet() -> String? {
        defaultInterface().flatMap(subnet(from:))
    }

    public static func defaultInterface() -> NetworkInterfaceInfo? {
        let candidates = scannableInterfaces()
        return candidates.first(where: { $0.name == "en0" }) ?? candidates.first(where: { $0.name == "en1" }) ?? candidates.first
    }

    /// Active interfaces likely to host a useful subnet: Ethernet/Wi-Fi, bridges and VPNs with /16…/30 masks.
    public static func scannableInterfaces() -> [NetworkInterfaceInfo] {
        let nameAllow: [String] = ["en", "bridge", "utun", "ppp"]
        return activeInterfaces().filter { iface in
            guard nameAllow.contains(where: { iface.name.hasPrefix($0) }) else { return false }
            return iface.netmaskBits >= 16 && iface.netmaskBits <= 30
        }
    }

    public static func subnet(from info: NetworkInterfaceInfo) -> String? {
        guard let ipInt = IPv4.uint32(from: info.ipv4) else { return nil }
        let mask: UInt32 = info.netmaskBits == 0 ? 0 : UInt32.max << (32 - info.netmaskBits)
        return "\(IPv4.string(from: ipInt & mask))/\(info.netmaskBits)"
    }

    /// The address ranges directly attached to this Mac: ARP is authoritative there.
    public static func localRanges() -> [ScanRange] {
        scannableInterfaces().compactMap { subnet(from: $0) }.compactMap { ScanRange(cidr: $0) }
    }

    /// This Mac's own IPv4 addresses.
    public static func ownAddresses() -> Set<String> {
        Set(activeInterfaces().map(\.ipv4))
    }

    /// The default IPv4 gateway, from `route -n get default` (a system binary, ~10 ms).
    public static func defaultGateway() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("gateway:") else { continue }
            let value = trimmed.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
            return IPv4.uint32(from: value) != nil ? value : nil
        }
        return nil
    }
}

/// What this Mac says about itself.
public enum LocalMachine {
    /// `hw.model`, e.g. `Mac14,6`.
    public static let model: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()

    /// `Adriens-MacBook.local` as the system reports it.
    public static var hostName: String { ProcessInfo.processInfo.hostName }
}
