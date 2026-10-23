import AppKit
import Foundation
import SimpleScannerCore

/// Opens connections to a device with the Mac's own applications.
@MainActor
enum HostActions {
    enum Connection: String, CaseIterable, Identifiable {
        case http, https, ssh, vnc, smb, afp, rdp, telnet, ping
        var id: String { rawValue }

        var label: String {
            switch self {
            case .http: "HTTP"
            case .https: "HTTPS"
            case .ssh: "SSH"
            case .vnc: "Partage d'écran"
            case .smb: "SMB"
            case .afp: "AFP"
            case .rdp: "Bureau à distance"
            case .telnet: "Telnet"
            case .ping: "Ping dans Terminal"
            }
        }

        var symbol: String {
            switch self {
            case .http, .https: "globe"
            case .ssh: "terminal"
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

    static func open(_ connection: Connection, ip: String) {
        guard IPv4.uint32(from: ip) != nil else { return }
        switch connection {
        case .http: open(url: "http://\(ip)")
        case .https: open(url: "https://\(ip)")
        case .ssh: runInTerminal(name: "ssh-\(ip)", command: "ssh", arguments: ip)
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
            catch { notify("Connexion Bureau à distance impossible", error.localizedDescription) }
        }
    }

    static func wakeAll(macs: [String]) async {
        let result = await WakeOnLAN.wakeAll(macs: macs)
        notify("Wake-on-LAN", "Paquets envoyés : \(result.sent). Échecs : \(result.failed). L'envoi ne garantit pas que l'appareil s'est réveillé.")
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
            notify("Aucune application compatible", "Installez une application qui prend en charge ce type de connexion (\(url.scheme ?? url.pathExtension)).")
            return
        }
        if !NSWorkspace.shared.open(url) { notify("Ouverture impossible", "L'application choisie n'a pas pu ouvrir cette connexion.") }
    }

    private static func runInTerminal(name: String, command: String, arguments: String) {
        let paths = ["/usr/bin/", "/sbin/", "/opt/homebrew/bin/", "/usr/local/bin/"]
        guard let executable = paths.map({ $0 + command }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            notify("Commande indisponible", "La commande \(command) n'est pas installée sur ce Mac.")
            return
        }
        let url = cacheDir.appendingPathComponent("\(name).command")
        let script = "#!/bin/bash\n\(executable) \(arguments)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            notify("Préparation de la commande impossible", error.localizedDescription)
            return
        }
        open(url)
    }
}
