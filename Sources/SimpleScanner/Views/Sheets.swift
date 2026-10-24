import SimpleScannerCore
import SwiftUI

struct ExportSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exporter les résultats").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            SectionHeader("Format")
            VStack(spacing: 4) {
                ForEach(AppModel.ExportFormat.allCases) { format in
                    let active = model.exportFormat == format
                    Button { model.exportFormat = format } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: active ? "largecircle.fill.circle" : "circle").font(.system(size: 12)).foregroundStyle(active ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text.swiftUI)
                                Text(format.detail).font(.system(size: 10.5)).foregroundStyle(Theme.textDim.swiftUI)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.laneSelected.swiftUI : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            SectionHeader("Contenu")
            HStack(spacing: 4) {
                scopeButton("Lignes affichées (\(model.visibleHosts.count))", selected: model.exportVisibleOnly) { model.exportVisibleOnly = true }
                scopeButton("Tous les appareils (\(model.scan.aliveCount))", selected: !model.exportVisibleOnly) { model.exportVisibleOnly = false }
            }
            HStack {
                Button("Annuler") { model.showExport = false }.keyboardShortcut(.cancelAction)
                Spacer()
                TextButton(title: "Copier", symbol: "doc.on.doc") { model.copyExport() }
                TextButton(title: "Enregistrer…", symbol: "square.and.arrow.down", prominent: true) { model.saveExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func scopeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.accent.swiftUI : Color.white.opacity(0.05)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PortScanSheet: View {
    @Bindable var model: AppModel
    @State private var error: String?

    private var presets: [(String, String)] {
        [("Courants", PortScanner.defaultPortsInput), ("Web", PortScanner.webPortsInput), ("1–1024", PortScanner.wideRangeInput)]
    }

    var body: some View {
        let count = model.portScanTargets.count
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyser les ports").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            Text(Format.count(count, "appareil") + " · connexions TCP directes, sans privilèges").font(.system(size: 11.5)).foregroundStyle(Theme.textDim.swiftUI)
            SectionHeader("Ports")
            HStack(spacing: 4) {
                ForEach(presets, id: \.0) { preset in
                    let active = model.portsInput == preset.1
                    Button { model.portsInput = preset.1; error = nil } label: {
                        Text(preset.0).font(.system(size: 11, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(active ? Theme.accent.swiftUI : Color.white.opacity(0.05)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            CommitField(value: model.portsInput, placeholder: "22, 80, 443, 8000-8100", monospaced: true) { model.portsInput = $0; error = nil }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.danger.swiftUI)
            } else if let ports = PortScanner.parsePorts(model.portsInput) {
                Text("\(Format.count(ports.count, "port")) par appareil").font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            }
            Toggle(isOn: $model.fetchBanners) {
                Text("Lire les titres HTTP et bannières SSH").font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            }
            .toggleStyle(.checkbox)
            HStack {
                Button("Annuler") { model.showPortScan = false }.keyboardShortcut(.cancelAction)
                Spacer()
                TextButton(title: "Lancer l'analyse", symbol: "scope", prominent: true, disabled: count == 0) {
                    if !model.startPortScan() { error = "Liste invalide. Exemple : 22, 80, 443, 8000-8100" }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Scan")
            FieldRow("Profil par défaut", width: 130) {
                Picker("", selection: $model.defaultProfile) {
                    ForEach(ScanProfile.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            Text(model.defaultProfile.description).font(.system(size: 10.5)).foregroundStyle(Theme.textFaint.swiftUI).padding(.leading, 138)
            FieldRow("Rescan automatique", width: 130) {
                Picker("", selection: $model.rescanInterval) {
                    ForEach(RescanInterval.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            Divider().overlay(Theme.separator.swiftUI)
            SectionHeader("Affichage")
            Toggle("Afficher les adresses sans réponse", isOn: $model.showDeadHosts).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle("Barre latérale", isOn: $model.showSidebar).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle("Fiche de l'appareil", isOn: $model.showInspector).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Divider().overlay(Theme.separator.swiftUI)
            SectionHeader("Confidentialité")
            Text("SimpleScanner n'envoie rien hors de votre réseau : pas de télémétrie, pas de compte, pas de mise à jour automatique. La base des fabricants (registre IEEE) est embarquée.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 360)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

struct ShortcutsSheet: View {
    let close: () -> Void

    static let groups: [(String, [(String, String)])] = [
        ("Scan", [
            ("⌘R", "Scanner le réseau"),
            ("⏎ (plage)", "Lancer le scan depuis le champ de plage"),
            ("⌘.", "Arrêter le scan"),
            ("⌘1 / ⌘2 / ⌘3", "Profil Rapide / Standard / Approfondi (menu Présentation)"),
            ("⌘I", "Importer une liste de cibles"),
            ("⌘O", "Ouvrir un scan enregistré"),
            ("⌘S", "Enregistrer le scan"),
            ("⇧⌘O", "Comparer à un scan enregistré"),
            ("⌘E", "Exporter (CSV, JSON, IP:port, texte)"),
        ]),
        ("Appareils", [
            ("↑ / ↓", "Parcourir la liste"),
            ("⇧-clic, ⌘-clic", "Sélection multiple"),
            ("Double-clic", "Ouvrir la fiche de l'appareil"),
            ("⏎", "Nommer l'appareil sélectionné"),
            ("⌘C", "Copier la ou les adresses IP"),
            ("⌘A", "Tout sélectionner"),
            ("⇧⌘R", "Actualiser la sélection"),
            ("⌘P", "Analyser les ports de la sélection"),
            ("⇧⌘W", "Wake-on-LAN"),
            ("⌘⌫", "Retirer de la liste"),
            ("Clic droit", "Se connecter : HTTP, SSH, SMB, VNC, RDP…"),
        ]),
        ("Fenêtre", [
            ("⌘F", "Rechercher (adresse, nom, fabricant, MAC, service)"),
            ("⎋", "Effacer la recherche"),
            ("⌥⌘S", "Barre latérale : réseaux, favoris, Bonjour, filtres"),
            ("⌥⌘I", "Fiche de l'appareil"),
            ("⇧⌘D", "Afficher les adresses sans réponse"),
            ("Clic en-tête", "Trier par cette colonne"),
            ("⌘,", "Préférences"),
            ("⌘? / ⌘/", "Aide / cette liste"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Raccourcis clavier").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textFaint.swiftUI)
            }
            HStack(alignment: .top, spacing: 24) {
                ForEach(Self.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.0.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(Theme.textFaint.swiftUI).padding(.bottom, 2)
                        ForEach(group.1, id: \.0) { key, text in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(key).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.accent.swiftUI).frame(width: 104, alignment: .leading)
                                Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(width: 262, alignment: .topLeading)
                }
            }
            Text("Astuce : un nom qui contient #scène ou #régie se retrouve avec la recherche, et le filtre « Appareils nommés » ne montre que les appareils étiquetés.")
                .font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            HStack { Spacer(); Button("OK", action: close).keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

struct AboutSheet: View {
    @Bindable var model: AppModel
    let openHelp: () -> Void
    let close: () -> Void
    @State private var copiedVersion = false

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let tint: NSColor
        let title: String
        let detail: String
    }

    private static let features: [Feature] = [
        Feature(icon: "dot.radiowaves.left.and.right", tint: Theme.accent, title: "Découverte en un souffle", detail: "Un socket ICMP, une rafale espacée, la table ARP du noyau comme juge : un /24 en une à deux secondes, sans privilèges."),
        Feature(icon: "person.text.rectangle", tint: Theme.bonjour, title: "Qui est qui", detail: "Nom DNS, NetBIOS, Bonjour et modèle matériel, fabricant par le registre IEEE embarqué, type d'appareil estimé avec ses indices."),
        Feature(icon: "scope", tint: Theme.tcp, title: "Ports, bannières, ping", detail: "Analyse TCP par préréglages, titres HTTP et bannières SSH, ping en direct avec sparkline, connexions en un clic."),
        Feature(icon: "clock.arrow.2.circlepath", tint: Theme.alive, title: "Mémoire du réseau", detail: "Noms persistants par adresse MAC, favoris, scans enregistrés et comparés (+ nouveaux, ~ modifiés, − disparus), exports CSV/JSON/texte."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                appIcon
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("SimpleScanner").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                        versionBadge
                    }
                    Text("Scanner réseau natif, ultra-léger et rapide pour macOS — dans la lignée de SimpleAudio et SimpleRecorder")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textDim.swiftUI)
                    HStack(spacing: 8) {
                        pill(icon: "bolt.fill", text: ICMPPinger.shared != nil ? "ICMP natif" : "ICMP indisponible", tint: ICMPPinger.shared != nil ? Theme.alive : Theme.textFaint)
                        pill(icon: "antenna.radiowaves.left.and.right", text: model.mdns.isRunning ? "Bonjour à l'écoute" : "Bonjour arrêté", tint: model.mdns.isRunning ? Theme.bonjour : Theme.textFaint)
                        pill(icon: "building.2", text: OUILookup.shared.isAvailable ? "\(OUILookup.shared.entryCount / 1000) k fabricants" : "registre absent", tint: Theme.accent)
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("CE QU'IL FAIT").font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(Theme.textFaint.swiftUI)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.features) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(item.tint.swiftUI)
                                .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 6).fill(item.tint.swiftUI.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                                Text(item.detail).font(.system(size: 10.5)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    }
                }
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Adrien Mondot · cie Adrien M").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text.swiftUI)
                    Text("Licence GPL v3+. Issu d'iPScanner de Canberk Kılıçarslan (licence MIT). Registre des fabricants : IEEE Standards Association. Aucune télémétrie.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textFaint.swiftUI).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { close(); openHelp() } label: { Label("Guide (⌘?)", systemImage: "book.closed").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim.swiftUI)
                Button("OK", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x222731)), Color(nsColor: NSColor(hex: 0x0E1014))], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
            RadarView(active: false, size: 52)
        }
        .frame(width: 72, height: 72)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    private var versionBadge: some View {
        Button {
            HostActions.copy(AppVersion.current.cliLine)
            withAnimation { copiedVersion = true }
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); withAnimation { copiedVersion = false } }
        } label: {
            Text(copiedVersion ? "copié" : AppVersion.current.shortLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.background.swiftUI)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.swiftUI))
        }
        .buttonStyle(.plain)
        .help("Copier la version")
    }

    private func pill(icon: String, text: String, tint: NSColor) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint.swiftUI)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(tint.swiftUI.opacity(0.12)))
    }
}
