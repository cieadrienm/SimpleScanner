import AppKit
import Foundation
import SimpleScannerCore

/// Opens connections to a device with the Mac's own applications.
@MainActor
enum HostActions {
    enum Connection: String, CaseIterable, Identifiable {
        case http, https, ssh, sftp, vnc, smb, afp, rdp, telnet, ping
        var id: String { rawValue }

        var label: String {
            switch self {
            case .http: "HTTP"
            case .https: "HTTPS"
            case .ssh: "SSH"
            case .sftp: "SFTP"
            case .vnc: L("Partage d'écran", "Screen Sharing")
            case .smb: "SMB"
            case .afp: "AFP"
            case .rdp: L("Bureau à distance", "Remote Desktop")
            case .telnet: "Telnet"
            case .ping: L("Ping dans Terminal", "Ping in Terminal")
            }
        }

        var symbol: String {
            switch self {
            case .http, .https: "globe"
            case .ssh: "terminal"
            case .sftp: "arrow.down.doc"
            case .vnc: "display"
            case .smb, .afp: "folder"
            case .rdp: "pc"
            case .telnet: "terminal.fill"
            case .ping: "waveform.path.ecg"
            }
        }

        /// Ports that suggest the connection makes sense.
        var ports: [Int] {
            switch self {
            case .http: [80, 8080, 8000, 8008, 8081, 8888]
            case .https: [443, 8443]
            case .ssh: [22]
            case .sftp: []
            case .vnc: [5900]
            case .smb: [445, 139]
            case .afp: [548]
            case .rdp: [3389]
            case .telnet: [23]
            case .ping: []
            }
        }
    }

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SimpleScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// What clicking a Bonjour service chip opens, if anything.
    nonisolated static func action(forService displayType: String, port: Int?) -> (connection: Connection, port: Int?)? {
        switch displayType {
        case "SSH": (.ssh, nil)
        case "SFTP": (.sftp, nil)
        case "Partage d'écran", "Screen Sharing": (.vnc, nil)
        case "SMB": (.smb, nil)
        case "AFP": (.afp, nil)
        case "HTTP", "OSCQuery": (.http, port)
        case "HTTPS": (.https, port)
        case "IPP", "Imprimante", "Impression", "Printer", "Printing", "Scanner", "Philips Hue": (.http, nil)
        default: nil
        }
    }

    /// What clicking an open-port chip opens, if anything.
    nonisolated static func action(forPort port: Int) -> (connection: Connection, port: Int?)? {
        switch port {
        case 22: (.ssh, nil)
        case 23: (.telnet, nil)
        case 80: (.http, nil)
        case 443: (.https, nil)
        case 445, 139: (.smb, nil)
        case 548: (.afp, nil)
        case 5900: (.vnc, nil)
        case 3389: (.rdp, nil)
        case 631, 1400, 3000, 5000, 8000, 8008, 8080, 8081, 8888, 9090, 10000, 32400: (.http, port)
        case 5001, 8006, 8443: (.https, port)
        default: nil
        }
    }

    static func open(_ connection: Connection, ip: String, port: Int? = nil) {
        guard IPv4.uint32(from: ip) != nil else { return }
        let suffix = port.map { ":\($0)" } ?? ""
        switch connection {
        case .http: open(url: "http://\(ip)\(suffix)")
        case .https: open(url: "https://\(ip)\(suffix)")
        case .ssh: runInTerminal(name: "ssh-\(ip)", command: "ssh", arguments: ip)
        case .sftp: runInTerminal(name: "sftp-\(ip)", command: "sftp", arguments: ip)
        case .vnc: open(url: "vnc://\(ip)")
        case .smb: open(url: "smb://\(ip)")
        case .afp: open(url: "afp://\(ip)")
        case .telnet: runInTerminal(name: "telnet-\(ip)", command: "telnet", arguments: ip)
        case .ping: runInTerminal(name: "ping-\(ip)", command: "ping", arguments: ip)
        case .rdp:
            if let url = URL(string: "rdp://full%20address=s:\(ip)"), NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                open(url)
                return
            }
            let url = cacheDir.appendingPathComponent("\(ip).rdp")
            let body = "full address:s:\(ip)\nscreen mode id:i:2\nprompt for credentials:i:1\n"
            do { try body.write(to: url, atomically: true, encoding: .utf8); open(url) }
            catch { notify(L("Connexion Bureau à distance impossible", "Remote Desktop connection failed"), error.localizedDescription) }
        }
    }

    static func wakeAll(macs: [String]) async {
        let result = await WakeOnLAN.wakeAll(macs: macs)
        notify("Wake-on-LAN", L("Paquets envoyés : \(result.sent). Échecs : \(result.failed). L'envoi ne garantit pas que l'appareil s'est réveillé.", "Packets sent: \(result.sent). Failed: \(result.failed). Sending a packet does not guarantee the device woke up."))
    }

    static func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private static func open(url string: String) {
        guard let url = URL(string: string) else { return }
        open(url)
    }

    private static func open(_ url: URL) {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            notify(L("Aucune application compatible", "No compatible application"), L("Installez une application qui prend en charge ce type de connexion (\(url.scheme ?? url.pathExtension)).", "Install an application that supports this connection type (\(url.scheme ?? url.pathExtension))."))
            return
        }
        if !NSWorkspace.shared.open(url) { notify(L("Ouverture impossible", "Could not open connection"), L("L'application choisie n'a pas pu ouvrir cette connexion.", "The selected application could not open this connection.")) }
    }

    private static func runInTerminal(name: String, command: String, arguments: String) {
        let paths = ["/usr/bin/", "/sbin/", "/opt/homebrew/bin/", "/usr/local/bin/"]
        guard let executable = paths.map({ $0 + command }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            notify(L("Commande indisponible", "Command unavailable"), L("La commande \(command) n'est pas installée sur ce Mac.", "The \(command) command is not installed on this Mac."))
            return
        }
        let url = cacheDir.appendingPathComponent("\(name).command")
        let script = "#!/bin/bash\n\(executable) \(arguments)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            notify(L("Préparation de la commande impossible", "Could not prepare command"), error.localizedDescription)
            return
        }
        open(url)
    }
}
