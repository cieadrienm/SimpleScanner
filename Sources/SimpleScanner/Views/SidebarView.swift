import SimpleScannerCore
import SwiftUI

/// Networks of this Mac, favourites, Bonjour families and quick filters.
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                networks
                Divider().overlay(Theme.separator.swiftUI)
                favourites
                Divider().overlay(Theme.separator.swiftUI)
                bonjour
                Divider().overlay(Theme.separator.swiftUI)
                filters
            }
            .padding(12)
        }
        .background(Theme.panel.swiftUI)
    }

    private var networks: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L("Réseaux de ce Mac", "This Mac's Networks"))
            let interfaces = NetworkInterface.scannableInterfaces()
            if interfaces.isEmpty {
                Text(L("Aucune interface active", "No active interface")).font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            }
            ForEach(interfaces, id: \.self) { iface in
                let active = model.scan.rangeInput == iface.cidr && model.scan.importedTargets == nil
                sidebarRow(active: active, symbol: iface.isVPN ? "lock.shield" : "wifi", title: iface.cidr, subtitle: "\(iface.name) · \(iface.ipv4)", mono: true) {
                    model.useInterface(iface)
                }
            }
        }
    }

    private var favourites: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L("Favoris", "Favorites")) {
                Button {
                    model.scan.toggleSaveCurrentRange()
                } label: {
                    Image(systemName: model.scan.isCurrentRangeSaved ? "star.slash" : "plus")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain)
                .disabled(model.scan.rangeInput.isEmpty || model.scan.importedTargets != nil)
                .help(model.scan.isCurrentRangeSaved ? L("Retirer la plage actuelle des favoris", "Remove current range from favorites") : L("Garder la plage actuelle", "Save current range"))
            }
            if model.scan.savedRanges.isEmpty {
                Text(L("Réseaux habituels enregistrés avec ☆ à côté de la plage.", "Saved networks marked with ☆ next to the range.")).font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.scan.savedRanges) { saved in
                let active = model.scan.rangeInput == saved.range && model.scan.importedTargets == nil
                sidebarRow(active: active, symbol: "star.fill", title: saved.displayTitle, subtitle: saved.name == nil ? nil : saved.range, mono: saved.name == nil) {
                    model.scan.loadSavedRange(saved.range)
                }
                .contextMenu {
                    Button(L("Renommer…", "Rename…")) { model.renamingRange = saved }
                    Button(L("Scanner maintenant", "Scan Now")) { model.scan.loadSavedRange(saved.range); model.startScan() }.disabled(model.scan.isScanning)
                    Divider()
                    Button(L("Retirer des favoris", "Remove from Favorites"), role: .destructive) { model.scan.removeSavedRange(saved.range) }
                }
            }
        }
    }

    private var bonjour: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L("Services Bonjour", "Bonjour Services")) {
                if model.scan.filterService != nil {
                    Button { model.scan.filterService = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI)
                    }
                    .buttonStyle(.plain)
                    .help(L("Ne plus filtrer par service", "Clear service filter"))
                }
            }
            let catalog = model.mdns.serviceCatalog
            if catalog.isEmpty {
                Text(model.mdns.isRunning ? L("À l'écoute du réseau…", "Listening on the network…") : L("Écoute Bonjour arrêtée", "Bonjour listening stopped")).font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            }
            ForEach(catalog, id: \.type) { entry in
                let active = model.scan.filterService == entry.type
                let shownType = MDNSDiscovery.displayService(entry.type)
                Button {
                    model.scan.filterService = active ? nil : entry.type
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.bonjour.swiftUI.opacity(active ? 1 : 0.5)).frame(width: 6, height: 6)
                        Text(shownType).font(.system(size: 11.5, weight: active ? .semibold : .regular)).foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI).lineLimit(1)
                        Spacer()
                        Text("\(entry.count)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textFaint.swiftUI).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(active ? Theme.bonjour.swiftUI.opacity(0.14) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("N'afficher que les appareils offrant \(shownType)", "Only show devices offering \(shownType)"))
            }
            .animation(.easeOut(duration: 0.2), value: catalog.map(\.type))
        }
    }

    private var filters: some View {
        @Bindable var scan = model.scan
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(L("Filtres", "Filters"))
            filterToggle(L("Ports ouverts", "Open ports"), symbol: "scope", isOn: $scan.filterHasOpenPorts)
            filterToggle(L("Appareils nommés", "Named devices"), symbol: "tag", isOn: $scan.filterHasLabel)
            filterToggle(L("Fabricant connu", "Known vendor"), symbol: "building.2", isOn: $scan.filterHasVendor)
            filterToggle(L("Type identifié", "Identified type"), symbol: "sparkles", isOn: $scan.filterIdentifiedDevice)
            filterToggle(L("Adresses sans réponse", "Unresponsive addresses"), symbol: "circle.dotted", isOn: $model.showDeadHosts)
        }
    }

    private func filterToggle(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(isOn.wrappedValue ? Theme.accent.swiftUI : Theme.textFaint.swiftUI).frame(width: 14)
                Text(title).font(.system(size: 11.5)).foregroundStyle(isOn.wrappedValue ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark" : "")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent.swiftUI)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(isOn.wrappedValue ? Theme.accent.swiftUI.opacity(0.10) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func sidebarRow(active: Bool, symbol: String, title: String, subtitle: String?, mono: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(active ? Theme.accent.swiftUI : Theme.textDim.swiftUI).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: active ? .semibold : .regular, design: mono ? .monospaced : .default)).foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textFaint.swiftUI).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(active ? Theme.laneSelected.swiftUI : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.scan.isScanning)
        .animation(.easeOut(duration: 0.15), value: active)
    }
}

struct RenameRangeSheet: View {
    let range: SavedRange
    let onCommit: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Nommer le favori", "Name Favorite")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            Text(range.range).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.textDim.swiftUI)
            TextField(L("Maison, Régie, Bureau…", "Home, Booth, Office…"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5)).foregroundStyle(Theme.text.swiftUI)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1))))
                .onSubmit { onCommit(name); dismiss() }
            HStack {
                Spacer()
                Button(L("Annuler", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Enregistrer", "Save")) { onCommit(name); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
        .onAppear { name = range.name ?? "" }
    }
}
