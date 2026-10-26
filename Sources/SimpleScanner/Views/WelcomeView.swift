import SimpleScannerCore
import SwiftUI

/// Before the first result: the radar, the range, and the three ways to start.
struct WelcomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            RadarView(active: model.scan.isScanning, size: 132)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                Text(model.scan.isScanning ? L("Découverte en cours", "Discovering Devices") : "SimpleScanner")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
            }
            .animation(.easeOut(duration: 0.25), value: model.scan.isScanning)

            if !model.scan.isScanning {
                HStack(spacing: 10) {
                    TextButton(title: L("Scanner \(model.scan.importedTargets == nil ? model.scan.rangeInput : "la liste")", "Scan \(model.scan.importedTargets == nil ? model.scan.rangeInput : "list")"), symbol: "dot.radiowaves.left.and.right", prominent: true, disabled: !model.scan.canStart) {
                        model.startScan()
                    }
                    TextButton(title: L("Ouvrir un scan…", "Open Scan…"), symbol: "folder") { model.openSnapshotPanel() }
                    TextButton(title: L("Importer des cibles…", "Import Targets…"), symbol: "doc.text") { model.importTargetsPanel() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if let warning = model.scan.warnings.first(where: { if case .localNetworkDenied = $0 { return true }; return false }) {
                VStack(spacing: 4) {
                    Label(warning.label, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent.swiftUI)
                    Text(warning.detail).font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI).multilineTextAlignment(.center)
                }
                .padding(12)
                .frame(maxWidth: 440)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.swiftUI.opacity(0.08)))
            }

            HStack(spacing: 18) {
                shortcutHint("⌘R", L("Scanner", "Scan"))
                shortcutHint("⌘F", L("Rechercher", "Find"))
                shortcutHint("⌥⌘I", L("Fiche", "Inspector"))
                shortcutHint("⌘P", L("Ports", "Ports"))
                shortcutHint("⌘E", L("Exporter", "Export"))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.swiftUI)
        .animation(.spring(duration: 0.35), value: model.scan.isScanning)
    }

    private var subtitle: String {
        if case .scanning(let scanned, let total) = model.scan.state, model.scan.phase == .discovery {
            return L("\(scanned) adresses sondées sur \(total)", "\(scanned) of \(total) addresses probed")
        }
        if model.scan.isScanning { return model.scan.phase.label }
        if case .done = model.scan.state { return L("Aucun appareil n'a répondu sur \(model.scan.rangeInput). Essayer le profil Standard, ou vérifier l'autorisation Réseau local.", "No device responded on \(model.scan.rangeInput). Try the Standard profile, or check Local Network permission.") }
        if let imported = model.scan.importedTargets { return L("\(Format.count(imported.targets.count, "cible")) depuis \(imported.url.lastPathComponent)", "\(Format.count(imported.targets.count, "target")) from \(imported.url.lastPathComponent)") }
        if model.scan.rangeInput.isEmpty { return L("Choisir un réseau dans la barre haute, ou saisir une plage d'adresses.", "Choose a network in the top bar, or enter an address range.") }
        return L("Les appareils de \(model.scan.rangeInput) apparaîtront ici au fil de la découverte.", "Devices on \(model.scan.rangeInput) will appear here as they are discovered.")
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text.swiftUI)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3.5).fill(Color.white.opacity(0.08)))
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
        }
    }
}
