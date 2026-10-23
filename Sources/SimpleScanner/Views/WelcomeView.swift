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
                Text(model.scan.isScanning ? "Découverte en cours" : "SimpleScanner")
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
                    TextButton(title: "Scanner \(model.scan.importedTargets == nil ? model.scan.rangeInput : "la liste")", symbol: "dot.radiowaves.left.and.right", prominent: true, disabled: !model.scan.canStart) {
                        model.startScan()
                    }
                    TextButton(title: "Ouvrir un scan…", symbol: "folder") { model.openSnapshotPanel() }
                    TextButton(title: "Importer des cibles…", symbol: "doc.text") { model.importTargetsPanel() }
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
                shortcutHint("⌘R", "Scanner")
                shortcutHint("⌘F", "Rechercher")
                shortcutHint("⌥⌘I", "Fiche")
                shortcutHint("⌘P", "Ports")
                shortcutHint("⌘E", "Exporter")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.swiftUI)
        .animation(.spring(duration: 0.35), value: model.scan.isScanning)
    }

    private var subtitle: String {
        if case .scanning(let scanned, let total) = model.scan.state, model.scan.phase == .discovery {
            return "\(scanned) adresses sondées sur \(total)"
        }
        if model.scan.isScanning { return model.scan.phase.rawValue }
        if case .done = model.scan.state { return "Aucun appareil n'a répondu sur \(model.scan.rangeInput). Essayez le profil Standard, ou vérifiez l'autorisation Réseau local." }
        if let imported = model.scan.importedTargets { return "\(Format.count(imported.targets.count, "cible")) depuis \(imported.url.lastPathComponent)" }
        if model.scan.rangeInput.isEmpty { return "Choisissez un réseau dans la barre haute, ou saisissez une plage d'adresses." }
        return "Les appareils de \(model.scan.rangeInput) apparaîtront ici au fil de la découverte."
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
