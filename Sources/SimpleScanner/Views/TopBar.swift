import SimpleScannerCore
import SwiftUI

/// Network, range, the scan button, the profile and the search field.
struct TopBar: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "sidebar.left", helpText: "Afficher ou masquer la barre latérale (⌥⌘S)", active: model.showSidebar) {
                model.showSidebar.toggle()
            }

            Divider().frame(height: 16).padding(.horizontal, 2)

            networkMenu
            rangeField
            IconButton(
                symbol: model.scan.isCurrentRangeSaved ? "star.fill" : "star",
                helpText: model.scan.isCurrentRangeSaved ? "Retirer ce réseau des favoris" : "Garder ce réseau en favori",
                tint: Theme.accent.swiftUI,
                disabled: model.scan.rangeInput.isEmpty || model.scan.importedTargets != nil
            ) {
                model.scan.toggleSaveCurrentRange()
            }
            .symbolEffect(.bounce, value: model.scan.isCurrentRangeSaved)

            Divider().frame(height: 16).padding(.horizontal, 2)

            scanButton
            profilePicker
            toolsMenu

            Spacer(minLength: 6)

            searchField

            IconButton(symbol: "sidebar.right", helpText: "Afficher ou masquer la fiche de l'appareil (⌥⌘I)", active: model.showInspector) {
                model.toggleInspector()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.panel.swiftUI)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
    }

    private var networkMenu: some View {
        Menu {
            ForEach(NetworkInterface.scannableInterfaces(), id: \.self) { iface in
                Button {
                    model.useInterface(iface)
                } label: {
                    Label("\(iface.name) · \(iface.cidr)  (\(iface.ipv4))", systemImage: iface.isVPN ? "lock.shield" : "wifi")
                }
            }
            if NetworkInterface.scannableInterfaces().isEmpty {
                Text("Aucune interface réseau active")
            }
            Divider()
            ForEach(model.scan.savedRanges) { saved in
                Button {
                    model.scan.loadSavedRange(saved.range)
                } label: {
                    Label(saved.displayTitle, systemImage: "star")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.currentInterface?.isVPN == true ? "lock.shield" : "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent.swiftUI)
                Text(model.currentInterface?.name ?? "Réseau")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.text.swiftUI)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textDim.swiftUI)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.scan.isScanning)
        .help("Choisir un réseau de ce Mac ou un favori")
    }

    @ViewBuilder
    private var rangeField: some View {
        if let imported = model.scan.importedTargets {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Theme.accent.swiftUI)
                Text(imported.url.lastPathComponent).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI).lineLimit(1)
                Text("\(imported.targets.count)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textDim.swiftUI)
                Button { model.scan.clearImportedFile() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain)
                .disabled(model.scan.isScanning)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.swiftUI.opacity(0.12)))
            .frame(maxWidth: 260)
        } else {
            CommitField(value: model.scan.rangeInput, placeholder: "192.168.1.0/24, 10.0.0.1-10.0.0.50", monospaced: true, onCommit: { text in
                model.setRange(text)
            }, onSubmit: { _ in
                if !model.scan.isScanning, model.scan.canStart { model.startScan() }
            })
            .frame(width: 236)
            .disabled(model.scan.isScanning)
            .help("Adresse, CIDR ou plage ; plusieurs valeurs séparées par des virgules. Entrée lance le scan.")
        }
    }

    private var scanButton: some View {
        Group {
            if model.scan.isScanning {
                TextButton(title: "Arrêter", symbol: "stop.fill", destructive: true) { model.scan.stop() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Theme.danger.swiftUI).frame(width: 6, height: 6)
                            .scaleEffect(pulse ? 1.3 : 0.8).opacity(pulse ? 0.4 : 1)
                            .offset(x: 2, y: -2)
                            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
                            .onDisappear { pulse = false }
                    }
            } else {
                TextButton(title: "Scanner", symbol: "dot.radiowaves.left.and.right", prominent: true, disabled: !model.scan.canStart) { model.startScan() }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.scan.isScanning)
        .help(model.scan.isScanning ? "Arrêter le scan (⌘.)" : "Découvrir les appareils (⌘R)")
    }

    private var profilePicker: some View {
        HStack(spacing: 2) {
            ForEach(ScanProfile.allCases) { profile in
                let active = model.defaultProfile == profile
                Button {
                    model.defaultProfile = profile
                } label: {
                    Text(profile.label)
                        .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(active ? Theme.accent.swiftUI : Color.clear))
                }
                .buttonStyle(.plain)
                .help(profile.description)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 5.5).fill(Color.white.opacity(0.05)))
        .animation(.easeOut(duration: 0.15), value: model.defaultProfile)
        .disabled(model.scan.isScanning)
    }

    private var toolsMenu: some View {
        Menu {
            Button("Importer une liste de cibles…") { model.importTargetsPanel() }.disabled(model.scan.isScanning)
            Button("Calculateur de sous-réseau…") {
                if model.subnetInput.isEmpty { model.subnetInput = model.scan.rangeInput }
                model.showSubnetCalculator = true
            }
            Divider()
            Button("Analyser les ports de la sélection…") { model.beginPortScan() }
                .disabled(model.scan.selection.isEmpty || model.scan.isScanning)
            Button("Wake-on-LAN sur la sélection") { model.wakeSelected() }
                .disabled(!model.scan.selectedHosts.contains { $0.mac != nil })
            Divider()
            Picker("Rescan automatique", selection: $model.rescanInterval) {
                ForEach(RescanInterval.allCases) { Text($0.menuLabel).tag($0) }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.swiftUI)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Outils : import, sous-réseau, ports, Wake-on-LAN, rescan")
        .popover(isPresented: $model.showSubnetCalculator, arrowEdge: .bottom) { SubnetCalculatorPopover(model: model) }
    }

    private var searchField: some View {
        @Bindable var scan = model.scan
        return HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
            TextField("Rechercher", text: $scan.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text.swiftUI)
                .focused($searchFocused)
                .onExitCommand { model.scan.searchQuery = ""; searchFocused = false }
            if !model.scan.searchQuery.isEmpty {
                Button { model.scan.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(searchFocused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .animation(.easeOut(duration: 0.15), value: model.scan.searchQuery.isEmpty)
        .help("Filtrer par adresse, nom, fabricant, MAC, modèle, service ou étiquette (⌘F)")
    }
}

struct SubnetCalculatorPopover: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Calculateur de sous-réseau")
            CommitField(value: model.subnetInput, placeholder: "10.0.0.0/24", monospaced: true) { model.subnetInput = $0 }
                .frame(width: 280)
            if let summary = SubnetCalculator.summarize(model.subnetInput) {
                VStack(alignment: .leading, spacing: 5) {
                    row("Réseau", summary.network)
                    row("Diffusion", summary.broadcast)
                    row("Hôtes", summary.firstHost.flatMap { f in summary.lastHost.map { "\(f) → \($0)" } } ?? "—")
                    row("Nombre", "\(summary.hostCount) utilisables")
                    row("Masque", summary.netmask)
                    row("Wildcard", summary.wildcard)
                }
                HStack {
                    Spacer()
                    TextButton(title: "Utiliser comme plage", symbol: "arrow.right", prominent: true, compact: true, disabled: model.scan.isScanning) {
                        model.setRange(summary.cidr)
                        model.showSubnetCalculator = false
                    }
                }
            } else if !model.subnetInput.isEmpty {
                Text("CIDR invalide. Essayez 10.0.0.0/24.").font(.system(size: 11)).foregroundStyle(Theme.danger.swiftUI)
            } else {
                Text("Saisissez un CIDR IPv4 pour voir réseau, diffusion et plage d'hôtes.").font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text.swiftUI).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
