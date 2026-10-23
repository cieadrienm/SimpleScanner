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
        CommandGroup(replacing: .appInfo) {
            Button("À propos de SimpleScanner") { model.showAbout = true }
        }

        CommandGroup(replacing: .newItem) {
            Button(model.scan.isScanning ? "Scan en cours…" : "Scanner le réseau") { model.startScan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.scan.canStart)
            Button("Arrêter le scan") { model.scan.stop() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.scan.isScanning)
            Divider()
            Button("Ouvrir un scan…") { model.openSnapshotPanel() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Enregistrer le scan…") { model.saveSnapshotPanel() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model.scan.hosts.isEmpty)
            Divider()
            Button("Comparer à un scan…") { model.compareSnapshotPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Effacer la comparaison") { model.scan.clearComparison() }
                .disabled(!model.scan.hasComparison)
            Divider()
            Button("Importer une liste de cibles…") { model.importTargetsPanel() }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(model.scan.isScanning)
            Button("Exporter…") { model.showExport = true }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(model.scan.hosts.isEmpty)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copier l'adresse IP") { model.copySelectedIPs() }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(model.scan.selection.isEmpty)
            Button("Tout sélectionner") { model.selectAll() }
                .keyboardShortcut("a", modifiers: [.command])
            Divider()
            Button("Rechercher") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command])
        }

        CommandMenu("Appareil") {
            Button("Nommer l'appareil…") { model.revealInspector(); model.labelFocusRequest += 1 }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.inspectedHost == nil)
            Button("Actualiser") { model.refreshSelected() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.scan.selection.isEmpty || model.scan.isScanning)
            Button("Analyser les ports…") { model.beginPortScan() }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(model.scan.selection.isEmpty || model.scan.isScanning)
            Button("Wake-on-LAN") { model.wakeSelected() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.scan.selectedHosts.contains { $0.mac != nil })
            Divider()
            Menu("Se connecter") {
                ForEach(HostActions.Connection.allCases) { connection in
                    Button(connection.label) {
                        if let host = model.inspectedHost { HostActions.open(connection, ip: host.ip) }
                    }
                }
            }
            .disabled(model.inspectedHost == nil)
            Divider()
            Button("Retirer de la liste") { model.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model.scan.selection.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button(model.showSidebar ? "Masquer la barre latérale" : "Afficher la barre latérale") { model.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button(model.showInspector ? "Masquer la fiche" : "Afficher la fiche") { model.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Afficher les adresses sans réponse", isOn: Binding(get: { model.showDeadHosts }, set: { model.showDeadHosts = $0 }))
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Menu("Profil de scan") {
                ForEach(Array(ScanProfile.allCases.enumerated()), id: \.element) { index, profile in
                    Button((model.defaultProfile == profile ? "✓ " : "") + profile.label) { model.defaultProfile = profile }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
            Picker("Rescan automatique", selection: Binding(get: { model.rescanInterval }, set: { model.rescanInterval = $0 })) {
                ForEach(RescanInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button("Aide SimpleScanner") { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command])
            Divider()
            Button("Raccourcis clavier") { model.showShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(startServices: !headless)
    private var headless = false
    private var didStart = false

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        let files = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
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
