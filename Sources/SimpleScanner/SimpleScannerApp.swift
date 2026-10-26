import AppKit
import SimpleScannerCore
import SwiftUI

@main
struct SimpleScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SimpleScanner") {
            ContentView(model: appDelegate.model)
                .frame(minWidth: 960, minHeight: 560)
                .onAppear { appDelegate.didAppear() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1340, height: 780)
        .commands { appCommands(model: appDelegate.model) }

        Settings {
            PreferencesView(model: appDelegate.model)
        }
    }

    @CommandsBuilder
    private func appCommands(model: AppModel) -> some Commands {
        let _ = model.language
        CommandGroup(replacing: .appInfo) {
            Button(L("À propos de SimpleScanner", "About SimpleScanner")) { model.showAbout = true }
            Button(L("Rechercher des mises à jour…", "Check for Updates…")) {
                model.showUpdater = true
                model.updater.checkForUpdates(silent: false)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(model.scan.isScanning ? L("Scan en cours…", "Scanning…") : L("Scanner le réseau", "Scan Network")) { model.startScan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.scan.canStart)
            Button(L("Arrêter le scan", "Stop Scan")) { model.scan.stop() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.scan.isScanning)
            Divider()
            Button(L("Ouvrir un scan…", "Open Scan…")) { model.openSnapshotPanel() }
                .keyboardShortcut("o", modifiers: [.command])
            Button(L("Enregistrer le scan…", "Save Scan…")) { model.saveSnapshotPanel() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model.scan.hosts.isEmpty)
            Divider()
            Button(L("Comparer à un scan…", "Compare with Scan…")) { model.compareSnapshotPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(L("Effacer la comparaison", "Clear Comparison")) { model.scan.clearComparison() }
                .disabled(!model.scan.hasComparison)
            Divider()
            Button(L("Importer une liste de cibles…", "Import Target List…")) { model.importTargetsPanel() }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(model.scan.isScanning)
            Button(L("Exporter…", "Export…")) { model.showExport = true }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(model.scan.hosts.isEmpty)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(L("Copier l'adresse IP", "Copy IP Address")) { model.copySelectedIPs() }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(model.scan.selection.isEmpty)
            Button(L("Tout sélectionner", "Select All")) { model.selectAll() }
                .keyboardShortcut("a", modifiers: [.command])
            Divider()
            Button(L("Rechercher", "Find")) { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command])
        }

        CommandMenu(L("Appareil", "Device")) {
            Button(L("Nommer l'appareil…", "Name Device…")) { model.revealInspector(); model.labelFocusRequest += 1 }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.inspectedHost == nil)
            Button(L("Actualiser", "Refresh")) { model.refreshSelected() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.scan.selection.isEmpty || model.scan.isScanning)
            Button(L("Analyser les ports…", "Scan Ports…")) { model.beginPortScan() }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(model.scan.selection.isEmpty || model.scan.isScanning)
            Button("Wake-on-LAN") { model.wakeSelected() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.scan.selectedHosts.contains { $0.mac != nil })
            Divider()
            Menu(L("Se connecter", "Connect")) {
                ForEach(HostActions.Connection.allCases) { connection in
                    Button(connection.label) {
                        if let host = model.inspectedHost { HostActions.open(connection, ip: host.ip) }
                    }
                }
            }
            .disabled(model.inspectedHost == nil)
            Divider()
            Button(L("Retirer de la liste", "Remove from List")) { model.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model.scan.selection.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button(model.showSidebar ? L("Masquer la barre latérale", "Hide Sidebar") : L("Afficher la barre latérale", "Show Sidebar")) { model.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button(model.showInspector ? L("Masquer la fiche", "Hide Inspector") : L("Afficher la fiche", "Show Inspector")) { model.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle(L("Afficher les adresses sans réponse", "Show Unresponsive Addresses"), isOn: Binding(get: { model.showDeadHosts }, set: { model.showDeadHosts = $0 }))
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Menu(L("Profil de scan", "Scan Profile")) {
                ForEach(Array(ScanProfile.allCases.enumerated()), id: \.element) { index, profile in
                    Button((model.defaultProfile == profile ? "✓ " : "") + profile.label) { model.defaultProfile = profile }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
            Picker(L("Rescan automatique", "Auto-Rescan"), selection: Binding(get: { model.rescanInterval }, set: { model.rescanInterval = $0 })) {
                ForEach(RescanInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button(L("Aide SimpleScanner", "SimpleScanner Help")) { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command])
            Divider()
            Button(L("Raccourcis clavier", "Keyboard Shortcuts")) { model.showShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
            Divider()
            Button(L("Site web Simple Apps (adrien-m.net/software)", "Simple Apps Website (adrien-m.net/software)")) {
                NSWorkspace.shared.open(URL(string: "https://adrien-m.net/software")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(startServices: !headless)
    private var headless = false
    private var didStart = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = Localization.current
        AppVersion.runIfRequested()
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--self-test") {
            headless = true
            SelfTest.runAndExit()
        }
        if let index = args.firstIndex(of: "--scan") {
            headless = true
            HeadlessScan.runAndExit(arguments: Array(args[(index + 1)...]))
        }
        if let index = args.firstIndex(of: "--snapshot") {
            headless = true
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("-") ? args[index + 1] : "/tmp/simplescanner.png"
            let view = args.firstIndex(of: "--view").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "results"
            Snapshot.runCLISnapshot(outputPath: path, view: view)
        }
    }

    func didAppear() {
        guard !didStart else { return }
        didStart = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let args = Array(CommandLine.arguments.dropFirst())
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--lang" || arg == "-AppleLanguage" || arg == "-AppleLanguages" || arg == "--view" {
                i += 2
                continue
            }
            if !arg.hasPrefix("-") { files.append(arg) }
            i += 1
        }
        if let first = files.first {
            let url = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) { model.open(url) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let first = urls.first { model.open(first) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.scan.stop()
        model.mdns.stop()
    }
}
