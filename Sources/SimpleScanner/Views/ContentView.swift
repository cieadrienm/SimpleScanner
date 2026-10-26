import SimpleScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        let _ = model.language
        VStack(spacing: 0) {
            TopBar(model: model)
            ScanProgressBar(fraction: model.scan.progressFraction, active: model.scan.isScanning, indeterminate: model.isIndeterminate)
                .background(Theme.panel.swiftUI)

            HStack(spacing: 0) {
                if model.showSidebar {
                    HStack(spacing: 0) {
                        SidebarView(model: model)
                            .frame(width: 222)
                        Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Group {
                    if model.scan.showsDiscoveryEmptyState {
                        WelcomeView(model: model)
                    } else {
                        DeviceList(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.swiftUI)
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.accent.swiftUI, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }

                if model.showInspector {
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                        InspectorView(model: model)
                            .frame(width: 300)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.spring(duration: 0.22, bounce: 0.0), value: model.showSidebar)
            .animation(.spring(duration: 0.22, bounce: 0.0), value: model.showInspector)

            StatusBar(model: model)
        }
        .id(model.language)
        .environment(\.locale, model.language.locale)
        .background(Theme.background.swiftUI)
        .preferredColorScheme(.dark)
        .navigationTitle("SimpleScanner")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $model.showExport) { ExportSheet(model: model).id(model.language) }
        .sheet(isPresented: $model.showPortScan) { PortScanSheet(model: model).id(model.language) }
        .sheet(isPresented: $model.showShortcuts) { ShortcutsSheet { model.showShortcuts = false }.id(model.language) }
        .sheet(isPresented: $model.showHelp) {
            HelpManualSheet(openShortcuts: { DispatchQueue.main.async { model.showShortcuts = true } }) { model.showHelp = false }
                .id(model.language)
        }
        .sheet(isPresented: $model.showAbout) {
            AboutSheet(model: model, openHelp: { DispatchQueue.main.async { model.showHelp = true } }) { model.showAbout = false }
                .id(model.language)
        }
        .sheet(isPresented: $model.showUpdater) {
            UpdateSheet(model: model) { model.showUpdater = false }
                .id(model.language)
        }
        .sheet(item: $model.renamingRange) { saved in
            RenameRangeSheet(range: saved) { name in model.scan.renameSavedRange(saved.range, to: name) }
                .id(model.language)
        }
        .alert(item: $model.alert) { alert in
            SwiftUI.Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: model.scan.selection) { _, selection in
            if selection.count != 1 { model.monitor.stop() }
        }
    }

    private var subtitle: String {
        if let imported = model.scan.importedTargets { return "\(imported.url.lastPathComponent) · \(Format.count(imported.targets.count, L("cible", "target")))" }
        if model.scan.isScanning { return "● \(model.scan.rangeInput)" }
        return model.scan.rangeInput
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u } else { url = nil }
                guard let url else { return }
                Task { @MainActor in
                    let ext = url.pathExtension.lowercased()
                    if ext == ScanSnapshot.fileExtension || url.lastPathComponent.hasSuffix(".ipscan.json") || ext == "json" {
                        model.open(url)
                    } else {
                        do {
                            let summary = try model.scan.loadImportedFile(url: url)
                            model.flash(L("\(Format.count(summary.targetCount, "cible")) importée\(summary.targetCount > 1 ? "s" : "")", "\(Format.count(summary.targetCount, "target")) imported"))
                        } catch {
                            model.alert = AppModel.Alert(title: L("Import impossible", "Could not import file"), message: error.localizedDescription)
                        }
                    }
                }
            }
        }
        return handled
    }
}
