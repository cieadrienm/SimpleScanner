import AppKit
import Foundation
import SimpleScannerCore

/// `SimpleScanner --scan <plage> [--input fichier] [--profile rapide|standard|approfondi] [--ports 22,80,8000-8100]
///  [--banners] [--format csv|json|txt|ip-port] [--output chemin] [--quiet]`: the engine without the window.
enum HeadlessScan {
    static var usage: String {
        L("""
        SimpleScanner --scan <plage> [options]
        SimpleScanner --scan --input <fichier> [options]

          --profile <quick|standard|deep>    Profondeur du scan (défaut : standard)
          --ports <liste>                    Ports à analyser, p. ex. 22,80,8000-8100
          --banners                          Lire les titres HTTP et bannières SSH
          --format <json|csv|txt|ip-port>    Format de sortie (défaut : json)
          --output <chemin>                  Écrire dans un fichier plutôt que sur stdout
          --lang <fr|en>                     Langue des messages et rapports
          --quiet                            Pas de progression sur stderr

        Codes de sortie : 0 succès · 1 argument invalide · 2 erreur d'exécution
        """, """
        SimpleScanner --scan <range> [options]
        SimpleScanner --scan --input <file> [options]

          --profile <quick|standard|deep>    Scan depth (default: standard)
          --ports <list>                     Ports to probe, e.g. 22,80,8000-8100
          --banners                          Fetch HTTP titles and SSH banners
          --format <json|csv|txt|ip-port>    Output format (default: json)
          --output <path>                    Write to a file instead of stdout
          --lang <fr|en>                     Language for messages and reports
          --quiet                            No progress on stderr

        Exit codes: 0 success · 1 invalid argument · 2 runtime error
        """)
    }

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
            guard i + 1 < argv.count else { throw OptionError.message(L("L'option \(flag) attend une valeur.", "Option \(flag) expects a value.")) }
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
                guard let profile = ScanProfile(rawValue: aliases[raw] ?? raw) else { throw OptionError.message(L("--profile : quick, standard ou deep.", "--profile: quick, standard, or deep.")) }
                options.profile = profile
            case "--ports":
                guard let ports = PortScanner.parsePorts(try value(token)) else { throw OptionError.message(L("--ports : par exemple 22,80,8000-8100.", "--ports: e.g. 22,80,8000-8100.")) }
                options.ports = ports
            case "--banners", "--fetch-banners": options.banners = true
            case "--format":
                let f = try value(token)
                guard ["json", "csv", "txt", "ip-port"].contains(f) else { throw OptionError.message(L("--format : json, csv, txt ou ip-port.", "--format: json, csv, txt, or ip-port.")) }
                options.format = f
            case "--output": options.output = try value(token)
            case "--lang", "-AppleLanguage":
                let langRaw = try value(token)
                if let lang = AppLanguage.parse(langRaw) { Localization.set(lang, persist: false) }
            case "--quiet": options.quiet = true
            default:
                if token.hasPrefix("--lang=") {
                    if let lang = AppLanguage.parse(String(token.dropFirst("--lang=".count))) { Localization.set(lang, persist: false) }
                } else if token.hasPrefix("-") {
                    throw OptionError.message(L("Option inconnue \(token).", "Unknown option \(token)."))
                } else if options.range == nil {
                    options.range = token
                } else {
                    throw OptionError.message(L("Argument inattendu « \(token) ».", "Unexpected argument “\(token)”."))
                }
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
                if !result.invalidLines.isEmpty, !options.quiet { stderr.write(Data(L("SimpleScanner: \(result.invalidLines.count) ligne(s) ignorée(s)\n", "SimpleScanner: \(result.invalidLines.count) line(s) skipped\n").utf8)) }
                targets = result.targets
            } catch { fail(error.localizedDescription, code: 1) }
        } else {
            let parsed = ScanRange.parseAll(options.range ?? "")
            if let bad = parsed.firstInvalidIndex { fail(L("Plage invalide (élément \(bad)).", "Invalid range (item \(bad))."), code: 1) }
            if ScanRange.totalHostCount(parsed.ranges) > ScanController.maxTargets { fail(L("Plage trop grande (max 65 536 adresses).", "Range too large (max 65,536 addresses)."), code: 1) }
            targets = ScanRange.uniqueAddresses(parsed.ranges)
        }
        if targets.isEmpty { fail(L("Aucune adresse à sonder.", "No address to probe."), code: 1) }

        Task.detached(priority: .userInitiated) {
            let started = Date()
            if !options.quiet { stderr.write(Data(L("SimpleScanner : \(targets.count) adresse(s), profil \(options.profile.label.lowercased())\n", "SimpleScanner: \(targets.count) address(es), \(options.profile.label.lowercased()) profile\n").utf8)) }
            var alive: [String: Host] = [:]
            var warnings: [ScanWarning] = []
            for await event in NetworkScanner(profile: options.profile).scan(addresses: targets) {
                switch event {
                case .host(let host) where host.status == .alive:
                    alive[host.ip] = alive[host.ip].map { $0.merged(with: host) } ?? host
                case .warning(let warning): warnings.append(warning)
                case .phase(let phase): if !options.quiet { stderr.write(Data("· \(phase.label)\n".utf8)) }
                case .sweep(let sent, let replies, let rejected, let neighbours):
                    if !options.quiet { stderr.write(Data(L("· ICMP : \(sent) envoyés, \(replies) réponses, \(rejected) rejetés par le noyau · \(neighbours) voisins ARP\n", "· ICMP: \(sent) sent, \(replies) replies, \(rejected) rejected by kernel · \(neighbours) ARP neighbors\n").utf8)) }
                default: break
                }
            }
            let ports = options.ports ?? (options.profile.autoPortScan ? PortScanner.commonPorts : nil)
            if let ports, !alive.isEmpty {
                if !options.quiet { stderr.write(Data(L("· Analyse de \(ports.count) port(s) sur \(alive.count) appareil(s)\n", "· Scanning \(ports.count) port(s) on \(alive.count) device(s)\n").utf8)) }
                for ip in alive.keys.sorted() {
                    let open = await PortScanner.probe(ip, ports: ports)
                    alive[ip]?.openPorts = open
                    if options.banners || (options.ports == nil && options.profile.autoPortScan), !open.isEmpty,
                       let title = await BannerProbe.fetch(ip, openPorts: open) {
                        alive[ip]?.serviceTitle = title
                    }
                }
            }
            for warning in warnings where !options.quiet { stderr.write(Data(L("Avertissement : \(warning.label)\n", "Warning: \(warning.label)\n").utf8)) }
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
            } catch { fail(L("Rendu impossible : \(error.localizedDescription)", "Could not render output: \(error.localizedDescription)"), code: 2) }
            if let path = options.output {
                do { try output.write(toFile: path, atomically: true, encoding: .utf8) } catch { fail(L("Écriture impossible : \(error.localizedDescription)", "Could not write file: \(error.localizedDescription)"), code: 2) }
            } else {
                FileHandle.standardOutput.write(Data(output.utf8))
            }
            if !options.quiet { stderr.write(Data(String(format: L("SimpleScanner : %d appareil(s) en %.1f s\n", "SimpleScanner: %d device(s) in %.1f s\n"), sorted.count, Date().timeIntervalSince(started)).utf8)) }
            exit(0)
        }
        RunLoop.main.run()
        exit(2)
    }
}
