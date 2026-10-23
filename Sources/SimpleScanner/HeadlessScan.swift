import AppKit
import Foundation
import SimpleScannerCore

/// `SimpleScanner --scan <plage> [--input fichier] [--profile rapide|standard|approfondi] [--ports 22,80,8000-8100]
///  [--banners] [--format csv|json|txt|ip-port] [--output chemin] [--quiet]`: the engine without the window.
enum HeadlessScan {
    static let usage = """
    SimpleScanner --scan <plage> [options]
    SimpleScanner --scan --input <fichier> [options]

      --profile <quick|standard|deep>    Profondeur du scan (défaut : standard)
      --ports <liste>                    Ports à analyser, p. ex. 22,80,8000-8100
      --banners                          Lire les titres HTTP et bannières SSH
      --format <json|csv|txt|ip-port>    Format de sortie (défaut : json)
      --output <chemin>                  Écrire dans un fichier plutôt que sur stdout
      --quiet                            Pas de progression sur stderr

    Codes de sortie : 0 succès · 1 argument invalide · 2 erreur d'exécution
    """

    struct Options {
        var range: String?
        var inputFile: String?
        var profile: ScanProfile = .standard
        var ports: [Int]?
        var banners = false
        var format = "json"
        var output: String?
        var quiet = false
    }

    enum OptionError: Error, CustomStringConvertible {
        case message(String)
        var description: String { if case .message(let m) = self { return m }; return "" }
    }

    static func parse(_ argv: [String]) throws -> Options {
        var options = Options()
        var i = 0
        func value(_ flag: String) throws -> String {
            guard i + 1 < argv.count else { throw OptionError.message("L'option \(flag) attend une valeur.") }
            i += 1
            return argv[i]
        }
        while i < argv.count {
            let token = argv[i]
            switch token {
            case "--input": options.inputFile = try value(token)
            case "--profile":
                let raw = try value(token)
                let aliases = ["rapide": "quick", "approfondi": "deep"]
                guard let profile = ScanProfile(rawValue: aliases[raw] ?? raw) else { throw OptionError.message("--profile : quick, standard ou deep.") }
                options.profile = profile
            case "--ports":
                guard let ports = PortScanner.parsePorts(try value(token)) else { throw OptionError.message("--ports : par exemple 22,80,8000-8100.") }
                options.ports = ports
            case "--banners", "--fetch-banners": options.banners = true
            case "--format":
                let f = try value(token)
                guard ["json", "csv", "txt", "ip-port"].contains(f) else { throw OptionError.message("--format : json, csv, txt ou ip-port.") }
                options.format = f
            case "--output": options.output = try value(token)
            case "--quiet": options.quiet = true
            default:
                if token.hasPrefix("-") { throw OptionError.message("Option inconnue \(token).") }
                if options.range == nil { options.range = token } else { throw OptionError.message("Argument inattendu « \(token) ».") }
            }
            i += 1
        }
        return options
    }

    /// Entry point from `applicationWillFinishLaunching`: never returns.
    static func runAndExit(arguments: [String]) -> Never {
        let stderr = FileHandle.standardError
        func fail(_ message: String, code: Int32) -> Never {
            stderr.write(Data("SimpleScanner: \(message)\n".utf8))
            exit(code)
        }
        let options: Options
        do { options = try parse(arguments) } catch { fail("\(error)\n\n\(usage)", code: 1) }
        if options.range == nil && options.inputFile == nil { fail(usage, code: 1) }

        let targets: [String]
        if let path = options.inputFile {
            do {
                let result = try TargetFileParser.parse(url: URL(fileURLWithPath: path))
                if !result.invalidLines.isEmpty, !options.quiet { stderr.write(Data("SimpleScanner: \(result.invalidLines.count) ligne(s) ignorée(s)\n".utf8)) }
                targets = result.targets
            } catch { fail(error.localizedDescription, code: 1) }
        } else {
            let parsed = ScanRange.parseAll(options.range ?? "")
            if let bad = parsed.firstInvalidIndex { fail("Plage invalide (élément \(bad)).", code: 1) }
            if ScanRange.totalHostCount(parsed.ranges) > ScanController.maxTargets { fail("Plage trop grande (max 65 536 adresses).", code: 1) }
            targets = ScanRange.uniqueAddresses(parsed.ranges)
        }
        if targets.isEmpty { fail("Aucune adresse à sonder.", code: 1) }

        Task.detached(priority: .userInitiated) {
            let started = Date()
            if !options.quiet { stderr.write(Data("SimpleScanner : \(targets.count) adresse(s), profil \(options.profile.label.lowercased())\n".utf8)) }
            var alive: [String: Host] = [:]
            var warnings: [ScanWarning] = []
            for await event in NetworkScanner(profile: options.profile).scan(addresses: targets) {
                switch event {
                case .host(let host) where host.status == .alive:
                    alive[host.ip] = alive[host.ip].map { $0.merged(with: host) } ?? host
                case .warning(let warning): warnings.append(warning)
                case .phase(let phase): if !options.quiet { stderr.write(Data("· \(phase.rawValue)\n".utf8)) }
                case .sweep(let sent, let replies, let rejected, let neighbours):
                    if !options.quiet { stderr.write(Data("· ICMP : \(sent) envoyés, \(replies) réponses, \(rejected) rejetés par le noyau · \(neighbours) voisins ARP\n".utf8)) }
                default: break
                }
            }
            let ports = options.ports ?? (options.profile.autoPortScan ? PortScanner.commonPorts : nil)
            if let ports, !alive.isEmpty {
                if !options.quiet { stderr.write(Data("· Analyse de \(ports.count) port(s) sur \(alive.count) appareil(s)\n".utf8)) }
                for ip in alive.keys.sorted() {
                    let open = await PortScanner.probe(ip, ports: ports)
                    alive[ip]?.openPorts = open
                    if options.banners || (options.ports == nil && options.profile.autoPortScan), !open.isEmpty,
                       let title = await BannerProbe.fetch(ip, openPorts: open) {
                        alive[ip]?.serviceTitle = title
                    }
                }
            }
            for warning in warnings where !options.quiet { stderr.write(Data("Avertissement : \(warning.label)\n".utf8)) }
            let sorted = alive.values.sorted { $0.ipNumeric < $1.ipNumeric }
            let rows = ExportService.rows(from: sorted) { _ in nil }
            let output: String
            do {
                switch options.format {
                case "csv": output = ExportService.csv(rows: rows)
                case "txt": output = ExportService.textReport(rows: rows, rangeInput: options.range ?? options.inputFile ?? "", scannedTotal: targets.count, aliveCount: sorted.count)
                case "ip-port": output = ExportService.ipPortList(rows: rows)
                default: output = String(decoding: try ExportService.json(rows: rows), as: UTF8.self) + "\n"
                }
            } catch { fail("Rendu impossible : \(error.localizedDescription)", code: 2) }
            if let path = options.output {
                do { try output.write(toFile: path, atomically: true, encoding: .utf8) } catch { fail("Écriture impossible : \(error.localizedDescription)", code: 2) }
            } else {
                FileHandle.standardOutput.write(Data(output.utf8))
            }
            if !options.quiet { stderr.write(Data(String(format: "SimpleScanner : %d appareil(s) en %.1f s\n", sorted.count, Date().timeIntervalSince(started)).utf8)) }
            exit(0)
        }
        RunLoop.main.run()
        exit(2)
    }
}
