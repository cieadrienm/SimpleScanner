import SimpleScannerCore
import SwiftUI

struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                if model.scan.isScanning {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                }
                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(model.scan.lastError != nil ? Theme.danger.swiftUI : Theme.textDim.swiftUI)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: model.statusMessage)
            }

            if let next = model.scan.nextRescanAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("rescan dans \(Format.elapsed(max(0, next.timeIntervalSince(context.date))))")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textFaint.swiftUI)
                }
            }

            Spacer()

            if let diff = model.scan.diff {
                Button { model.showDiff = true } label: {
                    HStack(spacing: 6) {
                        Text("+\(diff.newCount)").foregroundStyle(Theme.alive.swiftUI)
                        Text("~\(diff.modifiedCount)").foregroundStyle(Theme.changed.swiftUI)
                        Text("−\(diff.missingCount)").foregroundStyle(Theme.danger.swiftUI)
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Comparaison avec le scan du \(AppModel.dateFormatter.string(from: diff.baselineCreatedAt))")
                .popover(isPresented: $model.showDiff, arrowEdge: .top) { diffPopover(diff) }
                Divider().frame(height: 12)
            }

            if !model.scan.warnings.isEmpty {
                Button { model.showWarnings = true } label: {
                    Label(Format.count(model.scan.warnings.count, "avertissement"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.accent.swiftUI)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $model.showWarnings, arrowEdge: .top) { warningsPopover }
                Divider().frame(height: 12)
            }

            Text(summary)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint.swiftUI)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: summary)

            Divider().frame(height: 12)

            HStack(spacing: 12) {
                Button { model.showHelp = true } label: { Text("? aide") }
                    .buttonStyle(.plain).help("Guide d'utilisation (⌘?)")
                Button { model.showShortcuts = true } label: { Text("⌘/ raccourcis") }
                    .buttonStyle(.plain).help("Raccourcis clavier (⌘/)")
                Button { model.showAbout = true } label: {
                    Text(AppVersion.current.shortLabel).foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain).help("À propos de SimpleScanner \(AppVersion.current.description)")
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Theme.textFaint.swiftUI)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Theme.panel.swiftUI)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
    }

    private var summary: String {
        var parts: [String] = []
        let alive = model.scan.aliveCount
        let visible = model.visibleHosts.count
        if model.scan.hasResultConstraints, visible != alive {
            parts.append("\(visible)/\(alive) appareils")
        } else if alive > 0 || model.scan.hosts.count > 0 {
            parts.append(Format.count(alive, "appareil"))
        }
        if case .done(_, let total) = model.scan.state, total > 0 { parts.append(Format.count(total, "adresse")) }
        else if case .scanning(_, let total) = model.scan.state, total > 0 { parts.append(Format.count(total, "adresse")) }
        if model.scan.isScanning { parts.append(Format.elapsed(model.scan.elapsed)) }
        else if let duration = model.scan.lastDuration, duration > 0 { parts.append(Format.elapsed(duration)) }
        if !model.scan.selection.isEmpty { parts.append(Format.count(model.scan.selection.count, "sélectionné")) }
        return parts.joined(separator: " · ")
    }

    private var warningsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Avertissements")
            ForEach(Array(model.scan.warnings.enumerated()), id: \.offset) { _, warning in
                VStack(alignment: .leading, spacing: 3) {
                    Label(warning.label, systemImage: "exclamationmark.triangle").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text.swiftUI)
                    Text(warning.detail).font(.system(size: 10.5)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func diffPopover(_ diff: SnapshotDiff) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Comparaison") {
                Button("Effacer") { model.scan.clearComparison(); model.showDiff = false }.buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(Theme.accent.swiftUI)
            }
            Text("Référence : scan du \(AppModel.dateFormatter.string(from: diff.baselineCreatedAt))").font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI)
            HStack(spacing: 14) {
                diffStat(diff.newCount, "nouveaux", Theme.alive.swiftUI)
                diffStat(diff.modifiedCount, "modifiés", Theme.changed.swiftUI)
                diffStat(diff.missingCount, "disparus", Theme.danger.swiftUI)
            }
            if !diff.missingRecords.isEmpty {
                Divider().overlay(Theme.separator.swiftUI)
                Text("Disparus depuis la référence").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textDim.swiftUI)
                ForEach(diff.missingRecords.sorted { IPv4.uint32(from: $0.ip) ?? 0 < IPv4.uint32(from: $1.ip) ?? 0 }.prefix(12), id: \.self) { record in
                    HStack(spacing: 8) {
                        Text(record.ip).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text.swiftUI)
                        Text(record.hostname ?? record.vendor ?? record.mac ?? "").font(.system(size: 10.5)).foregroundStyle(Theme.textDim.swiftUI).lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func diffStat(_ n: Int, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(tint)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.textFaint.swiftUI)
        }
    }
}
