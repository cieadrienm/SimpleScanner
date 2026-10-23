import SimpleScannerCore
import SwiftUI

/// The selected device: identity, names, services, ports, live ping, actions.
struct InspectorView: View {
    @Bindable var model: AppModel
    @FocusState private var labelFocused: Bool
    @State private var labelText = ""
    @State private var savedFlash = false

    var body: some View {
        Group {
            if let host = model.inspectedHost {
                details(host)
            } else if model.scan.selection.count > 1 {
                multiSelection
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.panel.swiftUI)
        .onChange(of: model.inspectedHost?.id) { _, _ in syncLabel() }
        .onChange(of: model.inspectedHost?.mac) { _, _ in syncLabel() }
        .onAppear { syncLabel() }
        .onChange(of: model.labelFocusRequest) { _, _ in labelFocused = true }
    }

    private func syncLabel() {
        guard !labelFocused else { return }
        labelText = model.inspectedHost.flatMap { model.scan.label(for: $0) } ?? ""
    }

    private func commitLabel(_ host: Host) {
        let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (model.scan.label(for: host) ?? "") else { return }
        model.setLabel(trimmed, for: host)
        withAnimation(.easeOut(duration: 0.2)) { savedFlash = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { savedFlash = false }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func details(_ host: Host) -> some View {
        let classification = DeviceClassifier.assessment(host)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(host, classification: classification)
                labelSection(host)
                separator
                infoSection(host, classification: classification)
                if !host.services.isEmpty {
                    separator
                    servicesSection(host)
                }
                separator
                portsSection(host)
                separator
                pingSection(host)
                separator
                actionsSection(host)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(host.id)
        .transition(.opacity)
        .onAppear { if host.status != .dead { model.monitor.start(ip: host.ip) } }
        .onDisappear { model.monitor.stop() }
    }

    private var separator: some View {
        Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
    }

    private func header(_ host: Host, classification: DeviceClassification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accent.swiftUI.opacity(0.14))
                Image(systemName: classification.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent.swiftUI.opacity(classification.isCertain || classification.type == .unknown ? 1 : 0.75))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 46, height: 46)
            .help(classification.evidence)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.scan.title(for: host) ?? host.ip)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                    .lineLimit(2)
                Text(host.ip)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Circle().fill(Theme.status(host).swiftUI).frame(width: 6, height: 6)
                    Text(statusLine(host)).font(.system(size: 10.5)).foregroundStyle(Theme.textDim.swiftUI)
                    if classification.type != .unknown {
                        Text("·").foregroundStyle(Theme.textFaint.swiftUI)
                        Text((classification.isCertain ? "" : "probablement ") + classification.type.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textDim.swiftUI)
                    }
                    if let role = host.role {
                        Chip(text: role.label, tint: role == .thisMac ? Theme.accent.swiftUI : Theme.arp.swiftUI, filled: role == .thisMac)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusLine(_ host: Host) -> String {
        switch host.status {
        case .scanning: return "Vérification…"
        case .dead: return "Ne répond plus"
        case .alive:
            switch host.discoveredBy {
            case .arp: return "Présent, ping bloqué"
            case .tcp: return "Port ouvert, ping bloqué"
            default: return "En ligne"
            }
        }
    }

    private func labelSection(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Nom") {
                if savedFlash {
                    Label("Enregistré", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(Theme.alive.swiftUI)
                        .transition(.opacity)
                }
            }
            TextField("Nommer cet appareil, #tags acceptés", text: $labelText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.swiftUI)
                .focused($labelFocused)
                .onSubmit { commitLabel(host); labelFocused = false }
                .onChange(of: labelFocused) { _, focused in if !focused { commitLabel(host) } }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(labelFocused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                )
            Text(host.mac != nil ? "Mémorisé pour l'adresse MAC \(host.mac!)" : "Mémorisé pour l'adresse IP, faute d'adresse MAC")
                .font(.system(size: 10)).foregroundStyle(Theme.textFaint.swiftUI)
        }
    }

    private func infoSection(_ host: Host, classification: DeviceClassification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Identité")
            infoRow("Nom DNS", host.hostname)
            infoRow("NetBIOS", host.netbiosName.map { $0 + (host.workgroup.map { " · \($0)" } ?? "") })
            infoRow("Bonjour", host.bonjourName)
            infoRow("Modèle", host.model)
            infoRow("Adresse MAC", host.mac, mono: true)
            infoRow("Fabricant", host.vendor ?? host.vendorStatus?.label, dim: host.vendor == nil)
            infoRow("Service", host.serviceTitle)
            infoRow("Latence", host.rttMs.map(Format.latency), mono: true)
            infoRow("TTL", Format.ttlHint(host.ttl), mono: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(classification.type == .unknown ? "Type inconnu" : (classification.isCertain ? "Type : \(classification.type.label)" : "Type probable : \(classification.type.label)"))
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textDim.swiftUI)
                ForEach(classification.reasons.prefix(5), id: \.self) { reason in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•").foregroundStyle(Theme.accent.swiftUI.opacity(0.7))
                        Text(reason).font(.system(size: 10)).foregroundStyle(Theme.textFaint.swiftUI).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func infoRow(_ key: String, _ value: String?, mono: Bool = false, dim: Bool = false) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(key).font(.system(size: 11)).foregroundStyle(Theme.textDim.swiftUI).frame(width: 82, alignment: .leading)
                Text(value)
                    .font(.system(size: 11.5, design: mono ? .monospaced : .default))
                    .foregroundStyle(dim ? Theme.textFaint.swiftUI : Theme.text.swiftUI)
                    .textSelection(.enabled)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
    }

    private func servicesSection(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Services Bonjour")
            FlowLayout(spacing: 5) {
                ForEach(model.mdns.services(for: host.ip), id: \.self) { record in
                    Chip(text: "\(record.displayType) · \(record.name)", tint: Theme.bonjour.swiftUI)
                        .help(record.serviceType)
                }
                if model.mdns.services(for: host.ip).isEmpty {
                    ForEach(host.services, id: \.self) { Chip(text: $0, tint: Theme.bonjour.swiftUI) }
                }
            }
        }
    }

    private func portsSection(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Ports ouverts") {
                Button {
                    model.beginPortScan(ids: [host.id])
                } label: {
                    Label("Analyser…", systemImage: "scope").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.accent.swiftUI)
                }
                .buttonStyle(.plain)
                .disabled(model.scan.isScanning)
                .help("Analyser les ports de cet appareil (⌘P)")
            }
            if host.openPorts.isEmpty {
                Text(model.scan.portScanInProgress ? "Analyse en cours…" : "Aucun port connu. Lancez une analyse ou le profil Approfondi.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(host.openPorts, id: \.self) { port in
                        Chip(text: PortScanner.serviceName(for: port).map { "\(port) \($0)" } ?? "\(port)", tint: Theme.tcp.swiftUI)
                    }
                }
            }
        }
    }

    private func pingSection(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Ping en direct") {
                if let last = model.monitor.lastRTT {
                    Text(Format.latency(last)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.alive.swiftUI).contentTransition(.numericText())
                } else if !model.monitor.samples.isEmpty {
                    Text("perdu").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.danger.swiftUI)
                }
            }
            Sparkline(samples: model.monitor.samples)
                .frame(height: 44)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.3)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.06))))
            HStack(spacing: 12) {
                stat("moy.", model.monitor.avgRTT.map(Format.latency))
                stat("min", model.monitor.minRTT.map(Format.latency))
                stat("max", model.monitor.maxRTT.map(Format.latency))
                stat("perte", model.monitor.samples.isEmpty ? nil : "\(Int((model.monitor.lossRate * 100).rounded())) %")
            }
        }
    }

    private func stat(_ key: String, _ value: String?) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.system(size: 10)).foregroundStyle(Theme.textFaint.swiftUI)
            Text(value ?? "—").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textDim.swiftUI).contentTransition(.numericText())
        }
    }

    private func actionsSection(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Actions")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(HostActions.Connection.allCases) { connection in
                    let suggested = !Set(connection.ports).isDisjoint(with: host.openPorts) || host.services.contains(where: { suggests($0, connection) })
                    actionButton(connection.label, symbol: connection.symbol, highlighted: suggested) { HostActions.open(connection, ip: host.ip) }
                }
                actionButton("Wake-on-LAN", symbol: "power", highlighted: false, disabled: host.mac == nil) {
                    Task { await model.scan.runWakeOnLAN(for: [host.id]) }
                }
                actionButton("Actualiser", symbol: "arrow.clockwise", highlighted: false, disabled: model.scan.isScanning) {
                    model.scan.selection = [host.id]
                    model.refreshSelected()
                }
            }
            HStack(spacing: 6) {
                TextButton(title: "Copier l'IP", symbol: "doc.on.doc", compact: true) { model.copy(host.ip, what: "Adresse") }
                if let mac = host.mac { TextButton(title: "Copier la MAC", symbol: "doc.on.doc", compact: true) { model.copy(mac, what: "Adresse MAC") } }
                Spacer()
                TextButton(title: "Retirer", symbol: "trash", compact: true) { model.scan.deleteHosts([host.id]) }
            }
        }
    }

    private func suggests(_ service: String, _ connection: HostActions.Connection) -> Bool {
        switch connection {
        case .http: service == "HTTP"
        case .https: service == "HTTPS"
        case .ssh: service == "SSH" || service == "SFTP"
        case .vnc: service == "Partage d'écran"
        case .smb: service == "SMB"
        case .afp: service == "AFP"
        default: false
        }
    }

    private func actionButton(_ title: String, symbol: String, highlighted: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(disabled ? Theme.textFaint.swiftUI : (highlighted ? Theme.accent.swiftUI : Theme.text.swiftUI))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Theme.accent.swiftUI.opacity(0.12) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Other states

    private var multiSelection: some View {
        let hosts = model.scan.selectedHosts
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 20)).foregroundStyle(Theme.accent.swiftUI)
                Text(Format.count(hosts.count, "appareil sélectionné", "appareils sélectionnés")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
            }
            Text(hosts.prefix(12).map(\.ip).joined(separator: ", ") + (hosts.count > 12 ? ", …" : ""))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim.swiftUI)
            separator
            SectionHeader("Actions groupées")
            VStack(spacing: 6) {
                TextButton(title: "Analyser les ports…", symbol: "scope", disabled: model.scan.isScanning) { model.beginPortScan() }
                TextButton(title: "Actualiser", symbol: "arrow.clockwise", disabled: model.scan.isScanning) { model.refreshSelected() }
                TextButton(title: "Wake-on-LAN", symbol: "power", disabled: !hosts.contains { $0.mac != nil }) { model.wakeSelected() }
                TextButton(title: "Copier les adresses IP", symbol: "doc.on.doc") { model.copySelectedIPs() }
                TextButton(title: "Retirer de la liste", symbol: "trash") { model.deleteSelected() }
            }
            Spacer()
        }
        .padding(16)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "info.circle").font(.system(size: 26)).foregroundStyle(Theme.textFaint.swiftUI)
            Text("Sélectionnez un appareil").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textDim.swiftUI)
            Text("Sa fiche s'affichera ici : noms, fabricant, services, ports, ping en direct et actions.")
                .font(.system(size: 11)).foregroundStyle(Theme.textFaint.swiftUI).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
    }
}

/// Wraps chips on as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
