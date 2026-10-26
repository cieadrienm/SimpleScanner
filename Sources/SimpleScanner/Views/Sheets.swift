import AppKit
import SimpleScannerCore
import SwiftUI

struct ExportSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Exporter les résultats", "Export results")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            SectionHeader(L("Format", "Format"))
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
            SectionHeader(L("Contenu", "Scope"))
            HStack(spacing: 4) {
                scopeButton(L("Lignes affichées (\(model.visibleHosts.count))", "Visible rows (\(model.visibleHosts.count))"), selected: model.exportVisibleOnly) { model.exportVisibleOnly = true }
                scopeButton(L("Tous les appareils (\(model.scan.aliveCount))", "All devices (\(model.scan.aliveCount))"), selected: !model.exportVisibleOnly) { model.exportVisibleOnly = false }
            }
            HStack {
                Button(L("Annuler", "Cancel")) { model.showExport = false }.keyboardShortcut(.cancelAction)
                Spacer()
                TextButton(title: L("Copier", "Copy"), symbol: "doc.on.doc") { model.copyExport() }
                TextButton(title: L("Enregistrer…", "Save…"), symbol: "square.and.arrow.down", prominent: true) { model.saveExport() }
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
        [(L("Courants", "Common"), PortScanner.defaultPortsInput), ("Web", PortScanner.webPortsInput), ("1–1024", PortScanner.wideRangeInput)]
    }

    var body: some View {
        let count = model.portScanTargets.count
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Analyser les ports", "Scan Ports")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            Text(Format.count(count, L("appareil", "device")) + L(" · connexions TCP directes, sans privilèges", " · direct unprivileged TCP connections")).font(.system(size: 11.5)).foregroundStyle(Theme.textDim.swiftUI)
            SectionHeader(L("Ports", "Ports"))
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
                Text(L("\(Format.count(ports.count, "port")) par appareil", "\(Format.count(ports.count, "port")) per device")).font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            }
            Toggle(isOn: $model.fetchBanners) {
                Text(L("Lire les titres HTTP et bannières SSH", "Read HTTP titles and SSH banners")).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            }
            .toggleStyle(.checkbox)
            HStack {
                Button(L("Annuler", "Cancel")) { model.showPortScan = false }.keyboardShortcut(.cancelAction)
                Spacer()
                TextButton(title: L("Lancer l'analyse", "Start Scan"), symbol: "scope", prominent: true, disabled: count == 0) {
                    if !model.startPortScan() { error = L("Liste invalide. Exemple : 22, 80, 443, 8000-8100", "Invalid list. Example: 22, 80, 443, 8000-8100") }
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
            SectionHeader(L("Scan", "Scan"))
            FieldRow(L("Profil par défaut", "Default profile"), width: 130) {
                Picker("", selection: $model.defaultProfile) {
                    ForEach(ScanProfile.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            Text(model.defaultProfile.description).font(.system(size: 10.5)).foregroundStyle(Theme.textFaint.swiftUI).padding(.leading, 138)
            FieldRow(L("Rescan automatique", "Auto-rescan"), width: 130) {
                Picker("", selection: $model.rescanInterval) {
                    ForEach(RescanInterval.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            Divider().overlay(Theme.separator.swiftUI)
            SectionHeader(L("Affichage", "Display"))
            FieldRow(L("Langue", "Language"), width: 130) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            Toggle(L("Afficher les adresses sans réponse", "Show non-responding addresses"), isOn: $model.showDeadHosts).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Barre latérale", "Sidebar"), isOn: $model.showSidebar).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Fiche de l'appareil", "Device Inspector"), isOn: $model.showInspector).font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Divider().overlay(Theme.separator.swiftUI)
            SectionHeader(L("Mises à jour", "Updates"))
            HStack(alignment: .center, spacing: 12) {
                Toggle(L("Vérifier les mises à jour au lancement", "Check for updates on launch"), isOn: Binding(
                    get: { model.updater.autoCheckOnLaunch },
                    set: { model.updater.autoCheckOnLaunch = $0 }
                ))
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
                Spacer()
                TextButton(title: L("Vérifier maintenant…", "Check Now…"), symbol: "arrow.triangle.2.circlepath", compact: true) {
                    model.showUpdater = true
                    model.updater.checkForUpdates(silent: false)
                }
            }
            Divider().overlay(Theme.separator.swiftUI)
            SectionHeader(L("Confidentialité", "Privacy"))
            Text(L(
                "SimpleScanner n'envoie aucune donnée du réseau : pas de télémétrie, pas de compte. La base des fabricants (registre IEEE) est embarquée.",
                "SimpleScanner never sends your network data: no telemetry, no account. The vendor database (IEEE registry) is bundled offline."
            ))
                .font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

struct ShortcutsSheet: View {
    let close: () -> Void

    static var groups: [(String, [(String, String)])] {
        [
            (L("Scan", "Scan"), [
                ("⌘R", L("Scanner le réseau", "Scan network")),
                (L("⏎ (plage)", "⏎ (range)"), L("Lancer le scan depuis le champ de plage", "Start scan from the range field")),
                ("⌘.", L("Arrêter le scan", "Stop scan")),
                ("⌘1 / ⌘2 / ⌘3", L("Profil Rapide / Standard / Approfondi (menu Présentation)", "Fast / Standard / Deep profile (View menu)")),
                ("⌘I", L("Importer une liste de cibles", "Import target list")),
                ("⌘O", L("Ouvrir un scan enregistré", "Open saved scan")),
                ("⌘S", L("Enregistrer le scan", "Save scan")),
                ("⇧⌘O", L("Comparer à un scan enregistré", "Compare with saved scan")),
                ("⌘E", L("Exporter (CSV, JSON, IP:port, texte)", "Export (CSV, JSON, IP:port, text)")),
            ]),
            (L("Appareils", "Devices"), [
                ("↑ / ↓", L("Parcourir la liste", "Navigate list")),
                (L("⇧-clic, ⌘-clic", "⇧-click, ⌘-click"), L("Sélection multiple", "Multi-select")),
                (L("Double-clic", "Double-click"), L("Ouvrir la fiche de l'appareil", "Open device inspector")),
                ("⏎", L("Nommer l'appareil sélectionné", "Label selected device")),
                ("⌘C", L("Copier la ou les adresses IP", "Copy IP address(es)")),
                ("⌘A", L("Tout sélectionner", "Select all")),
                ("⇧⌘R", L("Actualiser la sélection", "Refresh selection")),
                ("⌘P", L("Analyser les ports de la sélection", "Scan ports on selection")),
                ("⇧⌘W", L("Wake-on-LAN", "Wake-on-LAN")),
                ("⌘⌫", L("Retirer de la liste", "Remove from list")),
                (L("Clic droit", "Right-click"), L("Se connecter : HTTP, SSH, SMB, VNC, RDP…", "Connect: HTTP, SSH, SMB, VNC, RDP…")),
            ]),
            (L("Fenêtre", "Window"), [
                ("⌘F", L("Rechercher (adresse, nom, fabricant, MAC, service)", "Search (IP, name, vendor, MAC, service)")),
                ("⎋", L("Effacer la recherche", "Clear search")),
                ("⌥⌘S", L("Barre latérale : réseaux, favoris, Bonjour, filtres", "Sidebar: networks, favorites, Bonjour, filters")),
                ("⌥⌘I", L("Fiche de l'appareil", "Device inspector")),
                ("⇧⌘D", L("Afficher les adresses sans réponse", "Show non-responding addresses")),
                (L("Clic en-tête", "Header click"), L("Trier par cette colonne", "Sort by column")),
                ("⌘,", L("Préférences", "Preferences")),
                ("⌘? / ⌘/", L("Aide / cette liste", "Help / this list")),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Raccourcis clavier", "Keyboard Shortcuts")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
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
            Text(L(
                "Astuce : un nom qui contient #scène ou #régie se retrouve avec la recherche, et le filtre « Appareils nommés » ne montre que les appareils étiquetés.",
                "Tip: a label containing #stage or #booth is searchable, and the “Labeled devices” filter shows only tagged devices."
            ))
                .font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            HStack { Spacer(); Button(L("OK", "OK"), action: close).keyboardShortcut(.defaultAction) }
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

    private static var features: [Feature] {
        [
            Feature(
                icon: "dot.radiowaves.left.and.right",
                tint: Theme.accent,
                title: L("Découverte en un souffle", "Discovery in a breath"),
                detail: L(
                    "Un socket ICMP, une rafale espacée, la table ARP du noyau comme juge : un /24 en une à deux secondes, sans privilèges.",
                    "One ICMP socket, a paced sweep, the kernel ARP table as arbiter: a /24 in one to two seconds, without privileges."
                )
            ),
            Feature(
                icon: "person.text.rectangle",
                tint: Theme.bonjour,
                title: L("Qui est qui", "Who is who"),
                detail: L(
                    "Nom DNS, NetBIOS, Bonjour et modèle matériel, fabricant par le registre IEEE embarqué, type d'appareil estimé avec ses indices.",
                    "DNS, NetBIOS, Bonjour name and hardware model, vendor from the bundled IEEE registry, estimated device type with clues."
                )
            ),
            Feature(
                icon: "scope",
                tint: Theme.tcp,
                title: L("Ports, bannières, ping", "Ports, banners, ping"),
                detail: L(
                    "Analyse TCP par préréglages, titres HTTP et bannières SSH, ping en direct avec sparkline, connexions en un clic.",
                    "Preset TCP port scans, HTTP titles and SSH banners, live ping with sparkline, one-click connections."
                )
            ),
            Feature(
                icon: "clock.arrow.2.circlepath",
                tint: Theme.alive,
                title: L("Mémoire du réseau", "Network memory"),
                detail: L(
                    "Noms persistants par adresse MAC, favoris, scans enregistrés et comparés (+ nouveaux, ~ modifiés, − disparus), exports CSV/JSON/texte.",
                    "Persistent labels by MAC address, favorites, saved and compared scans (+ new, ~ changed, − gone), CSV/JSON/text exports."
                )
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                appIcon
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("SimpleScanner").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                        versionBadge
                    }
                    Text(L(
                        "Scanner réseau natif, ultra-léger et rapide pour macOS — dans la lignée de SimpleAudio et SimpleRecorder",
                        "Fast, ultra-lightweight native network scanner for macOS — in the spirit of SimpleAudio and SimpleRecorder"
                    ))
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textDim.swiftUI)
                    HStack(spacing: 8) {
                        pill(icon: "bolt.fill", text: ICMPPinger.shared != nil ? L("ICMP natif", "Native ICMP") : L("ICMP indisponible", "ICMP unavailable"), tint: ICMPPinger.shared != nil ? Theme.alive : Theme.textFaint)
                        pill(icon: "antenna.radiowaves.left.and.right", text: model.mdns.isRunning ? L("Bonjour à l'écoute", "Bonjour listening") : L("Bonjour arrêté", "Bonjour stopped"), tint: model.mdns.isRunning ? Theme.bonjour : Theme.textFaint)
                        pill(icon: "building.2", text: OUILookup.shared.isAvailable ? L("\(OUILookup.shared.entryCount / 1000) k fabricants", "\(OUILookup.shared.entryCount / 1000)k vendors") : L("registre absent", "registry missing"), tint: Theme.accent)
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("CE QU'IL FAIT", "WHAT IT DOES")).font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(Theme.textFaint.swiftUI)
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
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://adrien-m.net")!)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Adrien Mondot · cie Adrien M — adrien-m.net")
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.text.swiftUI)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .help("https://adrien-m.net")

                        Text("·").font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)

                        Button {
                            NSWorkspace.shared.open(URL(string: "https://adrien-m.net/software")!)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                Text("Simple Apps")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent.swiftUI)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .help("https://adrien-m.net/software")
                    }
                    Text(L(
                        "Licence GPL v3+. Issu d'iPScanner de Canberk Kılıçarslan (licence MIT). Registre des fabricants : IEEE Standards Association. Aucune télémétrie.",
                        "GPL v3+ license. Derived from iPScanner by Canberk Kılıçarslan (MIT license). Vendor registry: IEEE Standards Association. Zero telemetry."
                    ))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textFaint.swiftUI).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    close()
                    DispatchQueue.main.async {
                        model.showUpdater = true
                        if case .updateAvailable = model.updater.state {
                            // Keep available release ready to install
                        } else {
                            model.updater.checkForUpdates(silent: false)
                        }
                    }
                } label: {
                    if case .updateAvailable(let rel) = model.updater.state {
                        Label(L("↑ Mise à jour v\(rel.version)", "↑ Update v\(rel.version)"), systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.accent.swiftUI)
                    } else {
                        Label(L("Mises à jour…", "Check for Updates…"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim.swiftUI)
                    }
                }
                .buttonStyle(.plain)
                Button { close(); openHelp() } label: { Label(L("Guide (⌘?)", "Guide (⌘?)"), systemImage: "book.closed").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim.swiftUI)
                Button(L("OK", "OK"), action: close).keyboardShortcut(.defaultAction)
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
            Text(copiedVersion ? L("copié", "copied") : AppVersion.current.shortLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.background.swiftUI)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.swiftUI))
        }
        .buttonStyle(.plain)
        .help(L("Copier la version", "Copy version"))
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

struct UpdateSheet: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x222731)), Color(nsColor: NSColor(hex: 0x0E1014))], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
                    RadarView(active: isWorking, size: 36)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Mises à jour de SimpleScanner", "SimpleScanner Updates"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Version installée : \(AppVersion.current.shortLabel)", "Installed version: \(AppVersion.current.shortLabel)"))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            statusContent

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack {
                Toggle(L("Vérifier automatiquement au lancement", "Automatically check on launch"), isOn: Binding(
                    get: { model.updater.autoCheckOnLaunch },
                    set: { model.updater.autoCheckOnLaunch = $0 }
                ))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
                .toggleStyle(.checkbox)

                Spacer()

                actionButtons
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var isWorking: Bool {
        switch model.updater.state {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.updater.state {
        case .idle:
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim.swiftUI)
                Text(L("Prêt à vérifier la disponibilité d'une mise à jour.", "Ready to check for available updates."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim.swiftUI)
            }
            .padding(.vertical, 8)

        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("Recherche de mises à jour en cours…", "Checking for updates…"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text.swiftUI)
            }
            .padding(.vertical, 8)

        case .upToDate(let version):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.alive.swiftUI)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("SimpleScanner est à jour (v\(version)).", "SimpleScanner is up to date (v\(version))."))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Cette version est à jour.", "This version is up to date."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
            }
            .padding(.vertical, 8)

        case .updateAvailable(let rel):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent.swiftUI)
                    Text(L("Nouvelle version disponible : v\(rel.version)", "New version available: v\(rel.version)"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    if let build = rel.build {
                        Text("(\(build))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textFaint.swiftUI)
                    }
                }

                if !rel.notes.isEmpty {
                    SectionHeader(L("Notes de version", "Release Notes"))
                    ScrollView {
                        Text(rel.notes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("Téléchargement de la mise à jour…", "Downloading update…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text.swiftUI)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(Theme.accent.swiftUI)
            }
            .padding(.vertical, 6)

        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("Vérification de la signature et installation…", "Verifying signature and installing…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text.swiftUI)
            }
            .padding(.vertical, 8)

        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.danger.swiftUI)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Échec de la vérification ou de la mise à jour", "Update check or installation failed"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch model.updater.state {
        case .updateAvailable(let rel):
            Button(L("Plus tard", "Later"), action: close)
                .keyboardShortcut(.cancelAction)
            TextButton(title: L("Mettre à jour et relancer", "Update & Relaunch"), symbol: "arrow.down.circle.fill", prominent: true) {
                model.updater.downloadAndInstall(rel)
            }
            .keyboardShortcut(.defaultAction)

        case .downloading, .installing:
            Button(L("Fermer", "Close"), action: close)
                .disabled(true)

        case .failed:
            Button(L("Fermer", "Close"), action: close)
                .keyboardShortcut(.cancelAction)
            TextButton(title: L("Réessayer", "Retry"), symbol: "arrow.clockwise", prominent: true) {
                model.updater.checkForUpdates(silent: false)
            }

        case .idle, .upToDate:
            TextButton(title: L("Vérifier à nouveau", "Check Again"), symbol: "arrow.triangle.2.circlepath", compact: true) {
                model.updater.checkForUpdates(silent: false)
            }
            Button(L("OK", "OK"), action: close)
                .keyboardShortcut(.defaultAction)

        case .checking:
            Button(L("Fermer", "Close"), action: close)
                .keyboardShortcut(.cancelAction)
        }
    }
}
