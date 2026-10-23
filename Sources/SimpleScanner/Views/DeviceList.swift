import AppKit
import SimpleScannerCore
import SwiftUI

/// The devices found, one row each, sortable from the header.
struct DeviceList: View {
    @Bindable var model: AppModel

    enum Column: CaseIterable {
        case status, ip, name, vendor, mac, services, latency

        var title: String {
            switch self {
            case .status: ""
            case .ip: "Adresse IP"
            case .name: "Nom"
            case .vendor: "Fabricant"
            case .mac: "Adresse MAC"
            case .services: "Services et ports"
            case .latency: "Latence"
            }
        }

        var width: CGFloat? {
            switch self {
            case .status: 46
            case .ip: 118
            case .name: nil
            case .vendor: 160
            case .mac: 130
            case .services: nil
            case .latency: 62
            }
        }

        /// The columns that fit: MAC steps aside first, then the vendor.
        static func visible(for width: CGFloat) -> [Column] {
            if width >= 900 { return allCases }
            if width >= 740 { return allCases.filter { $0 != .mac } }
            return allCases.filter { $0 != .mac && $0 != .vendor }
        }

        var sortKey: AppModel.SortKey? {
            switch self {
            case .status: nil
            case .ip: .ip
            case .name: .name
            case .vendor: .vendor
            case .mac: .mac
            case .services: .ports
            case .latency: .latency
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            list(columns: Column.visible(for: geo.size.width))
        }
    }

    @State private var anchorID: Host.ID?
    @FocusState private var listFocused: Bool

    private func list(columns: [Column]) -> some View {
        let rows = model.visibleHosts
        return VStack(spacing: 0) {
            header(columns: columns)
            if rows.isEmpty {
                emptyFiltered
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, host in
                                DeviceRow(
                                    host: host,
                                    columns: columns,
                                    title: model.scan.title(for: host),
                                    hasLabel: model.scan.label(for: host) != nil,
                                    change: model.scan.change(for: host),
                                    query: model.scan.searchQuery,
                                    selected: model.scan.selection.contains(host.id),
                                    alternate: index % 2 == 1,
                                    openService: { service in
                                        model.scan.selection = [host.id]
                                        model.open(service: service, of: host)
                                    },
                                    openPort: { port in
                                        model.scan.selection = [host.id]
                                        model.open(port: port, of: host)
                                    }
                                )
                                .id(host.id)
                                .onTapGesture { click(host, in: rows) }
                                .contextMenu {
                                    DeviceContextMenu(model: model, ids: model.scan.selection.contains(host.id) ? model.scan.selection : [host.id])
                                }
                                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.35, bounce: 0.1), value: rows.map(\.id))
                    }
                    .background(Theme.background.swiftUI)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.upArrow, phases: .down) { press in
                        move(by: -1, in: rows, extend: press.modifiers.contains(.shift), proxy: proxy)
                    }
                    .onKeyPress(.downArrow, phases: .down) { press in
                        move(by: 1, in: rows, extend: press.modifiers.contains(.shift), proxy: proxy)
                    }
                    .onKeyPress(.escape) { model.scan.selection = []; return .handled }
                }
            }
        }
    }

    /// Plain click selects; ⌘ toggles; ⇧ extends from the anchor; the second click of a double-click opens the inspector.
    private func click(_ host: Host, in rows: [Host]) {
        listFocused = true
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if NSApp.currentEvent?.clickCount == 2 {
            model.scan.selection = [host.id]
            anchorID = host.id
            model.revealInspector()
            return
        }
        if flags.contains(.command) {
            if model.scan.selection.contains(host.id) { model.scan.selection.remove(host.id) } else { model.scan.selection.insert(host.id) }
            anchorID = host.id
        } else if flags.contains(.shift), let anchorID, let a = rows.firstIndex(where: { $0.id == anchorID }), let b = rows.firstIndex(where: { $0.id == host.id }) {
            model.scan.selection = Set(rows[min(a, b)...max(a, b)].map(\.id))
        } else {
            model.scan.selection = [host.id]
            anchorID = host.id
        }
    }

    private func move(by delta: Int, in rows: [Host], extend: Bool, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let currentIndex = rows.lastIndex { model.scan.selection.contains($0.id) && (!extend || $0.id == anchorID) }
            ?? rows.lastIndex { model.scan.selection.contains($0.id) }
        let target: Int
        if let currentIndex { target = min(max(currentIndex + delta, 0), rows.count - 1) } else { target = delta > 0 ? 0 : rows.count - 1 }
        let host = rows[target]
        if extend, let anchorID, let a = rows.firstIndex(where: { $0.id == anchorID }) {
            model.scan.selection = Set(rows[min(a, target)...max(a, target)].map(\.id))
        } else {
            model.scan.selection = [host.id]
            anchorID = host.id
        }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(host.id) }
        return .handled
    }

    private func header(columns: [Column]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                let isSorted = column.sortKey == model.sortKey
                Button {
                    if let key = column.sortKey { model.toggleSort(key) }
                } label: {
                    HStack(spacing: 3) {
                        Text(column.title)
                            .font(.system(size: 10.5, weight: isSorted ? .semibold : .medium))
                            .foregroundStyle(isSorted ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        if isSorted {
                            Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.accent.swiftUI)
                                .transition(.scale.combined(with: .opacity))
                        }
                        if column == .latency { Spacer(minLength: 0) }
                    }
                    .frame(width: column.width, alignment: column == .latency ? .trailing : .leading)
                    .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
                    .padding(.horizontal, column == .status ? 0 : 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(column.sortKey == nil)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 26)
        .background(Theme.header.swiftUI)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
        .animation(.easeOut(duration: 0.15), value: model.sortKey)
        .animation(.easeOut(duration: 0.15), value: model.sortAscending)
    }

    private var emptyFiltered: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textFaint.swiftUI)
            Text(model.scan.hasActiveScopeFilters || !model.scan.searchQuery.isEmpty ? "Aucun appareil ne correspond" : "Aucun appareil")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textDim.swiftUI)
            if model.scan.hasActiveScopeFilters {
                TextButton(title: "Retirer les filtres (\(model.scan.activeFilterNames.joined(separator: ", ")))", compact: true) {
                    model.scan.clearScopeFilters()
                }
            }
            if !model.scan.searchQuery.isEmpty {
                TextButton(title: "Effacer la recherche", symbol: "xmark", compact: true) { model.scan.searchQuery = "" }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeviceRow: View {
    let host: Host
    let columns: [DeviceList.Column]
    let title: String?
    let hasLabel: Bool
    let change: HostChange?
    let query: String
    let selected: Bool
    let alternate: Bool
    var openService: ((String) -> Void)? = nil
    var openPort: ((Int) -> Void)? = nil

    private var classification: DeviceClassification { DeviceClassifier.assessment(host) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                cell(for: column)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 30)
        .background(
            ZStack(alignment: .leading) {
                (selected ? Theme.laneSelected.swiftUI : (alternate ? Theme.laneAlt.swiftUI : Theme.lane.swiftUI))
                if selected { Rectangle().fill(Theme.accent.swiftUI).frame(width: 2) }
            }
        )
        .opacity(host.status == .dead ? 0.55 : 1)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: selected)
        .animation(.easeOut(duration: 0.25), value: host.status)
    }

    @ViewBuilder
    private func cell(for column: DeviceList.Column) -> some View {
        switch column {
        case .status:
            statusCell.frame(width: DeviceList.Column.status.width)
        case .ip:
            cell(width: DeviceList.Column.ip.width) {
                Text(highlighted(host.ip))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text.swiftUI)
            }
        case .name:
            cell(width: nil) {
                HStack(spacing: 5) {
                    if let title {
                        Text(highlighted(title))
                            .font(.system(size: 11.5, weight: hasLabel ? .semibold : .regular))
                            .foregroundStyle(hasLabel ? Theme.accent.swiftUI : Theme.text.swiftUI)
                            .lineLimit(1)
                            .layoutPriority(1)
                    } else {
                        Text("—").font(.system(size: 11.5)).foregroundStyle(Theme.textFaint.swiftUI)
                    }
                    if let role = host.role {
                        Chip(text: role.label, tint: role == .thisMac ? Theme.accent.swiftUI : Theme.arp.swiftUI, filled: role == .thisMac).fixedSize()
                    }
                    if let model = host.model {
                        Text(model).font(.system(size: 10)).foregroundStyle(Theme.textFaint.swiftUI).lineLimit(1)
                    }
                    if let change {
                        Image(systemName: change.sfSymbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(changeTint(change))
                            .help(change.label)
                    }
                }
            }
        case .vendor:
            cell(width: DeviceList.Column.vendor.width) {
                Text(highlighted(host.vendor ?? vendorFallback))
                    .font(.system(size: 11))
                    .foregroundStyle(host.vendor == nil ? Theme.textFaint.swiftUI : Theme.textDim.swiftUI)
                    .lineLimit(1)
            }
        case .mac:
            cell(width: DeviceList.Column.mac.width) {
                Text(highlighted(host.mac ?? "—"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(host.mac == nil ? Theme.textFaint.swiftUI : Theme.textDim.swiftUI)
            }
        case .services:
            cell(width: nil) {
                let services = host.services.prefix(3), ports = host.openPorts.prefix(3)
                let hidden = (host.services.count - services.count) + (host.openPorts.count - ports.count)
                HStack(spacing: 4) {
                    ForEach(services, id: \.self) { service in
                        let action = HostActions.action(forService: service, port: nil)
                        ActionChip(text: service, tint: Theme.bonjour.swiftUI, help: action.map { "Ouvrir \($0.connection.label)" } ?? service, action: action == nil ? nil : { openService?(service) }).fixedSize()
                    }
                    ForEach(ports, id: \.self) { port in
                        let action = HostActions.action(forPort: port)
                        ActionChip(text: PortScanner.serviceName(for: port) ?? "\(port)", tint: Theme.tcp.swiftUI, help: action.map { "Port \(port) : ouvrir \($0.connection.label)" } ?? "Port \(port)", action: action == nil ? nil : { openPort?(port) }).fixedSize()
                    }
                    if hidden > 0 {
                        Text("+\(hidden)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textFaint.swiftUI).fixedSize()
                    }
                    if host.services.isEmpty && host.openPorts.isEmpty, let serviceTitle = host.serviceTitle {
                        Text(serviceTitle).font(.system(size: 10.5)).foregroundStyle(Theme.textFaint.swiftUI).lineLimit(1)
                    }
                }
            }
        case .latency:
            cell(width: DeviceList.Column.latency.width, alignment: .trailing) {
                Text(Format.latency(host.rttMs))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(latencyTint)
                    .contentTransition(.numericText())
            }
        }
    }

    private var statusCell: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().fill(Theme.status(host).swiftUI).frame(width: 7, height: 7)
                    .shadow(color: Theme.status(host).swiftUI.opacity(host.status == .alive ? 0.7 : 0), radius: 3)
                if host.status == .scanning {
                    Circle().strokeBorder(Theme.accent.swiftUI.opacity(0.5), lineWidth: 1).frame(width: 13, height: 13)
                }
            }
            .frame(width: 14)
            .help(statusHelp)
            let classification = classification
            Image(systemName: classification.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(classification.type == .unknown ? Theme.textFaint.swiftUI : Theme.textDim.swiftUI)
                .opacity(classification.type != .unknown && !classification.isCertain ? 0.7 : 1)
                .frame(width: 18)
                .help(classification.type == .unknown ? classification.evidence : (classification.isCertain ? classification.type.label : "Probablement : \(classification.type.label)"))
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func cell<Content: View>(width: CGFloat?, alignment: Alignment = .leading, @ViewBuilder content: () -> Content) -> some View {
        Group {
            if let width {
                content().frame(width: width, alignment: alignment)
            } else {
                content().frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
            }
        }
        .padding(.horizontal, 6)
        .clipped()
    }

    private var vendorFallback: String {
        if let mac = host.mac, MACAddress(mac)?.kind == .local { return "Adresse privée" }
        switch host.vendorStatus {
        case .localAddress: return "Adresse privée"
        case .notFound: return "Fabricant inconnu"
        default: return "—"
        }
    }

    private var statusHelp: String {
        switch host.status {
        case .scanning: return "Vérification en cours"
        case .dead: return "Aucune réponse"
        case .alive:
            switch host.discoveredBy {
            case .arp: return "Présent (répond à ARP, pas au ping)"
            case .tcp: return "Présent (port TCP ouvert, ping bloqué)"
            default: return "Répond au ping"
            }
        }
    }

    private var latencyTint: Color {
        guard let rtt = host.rttMs else { return Theme.textFaint.swiftUI }
        if rtt < 5 { return Theme.alive.swiftUI }
        if rtt < 50 { return Theme.textDim.swiftUI }
        return Theme.accent.swiftUI
    }

    private func changeTint(_ change: HostChange) -> Color {
        switch change {
        case .new: Theme.alive.swiftUI
        case .modified: Theme.changed.swiftUI
        case .missing: Theme.danger.swiftUI
        }
    }

    private func highlighted(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        guard !query.isEmpty, let range = attributed.range(of: query, options: [.caseInsensitive]) else { return attributed }
        attributed[range].backgroundColor = Theme.accent.swiftUI.opacity(0.35)
        return attributed
    }
}

struct DeviceContextMenu: View {
    @Bindable var model: AppModel
    let ids: Set<Host.ID>

    private var hosts: [Host] { model.scan.hosts.filter { ids.contains($0.id) } }

    var body: some View {
        if hosts.count == 1, let host = hosts.first {
            Button("Fiche de l'appareil") { model.scan.selection = ids; model.revealInspector() }
            Button("Nommer…") { model.scan.selection = ids; model.revealInspector(); model.labelFocusRequest += 1 }
            Divider()
            Menu("Se connecter") {
                ForEach(HostActions.Connection.allCases) { connection in
                    Button(connection.label, systemImage: connection.symbol) { HostActions.open(connection, ip: host.ip) }
                }
            }
            Button("Analyser les ports…") { model.beginPortScan(ids: ids) }.disabled(model.scan.isScanning)
            Button("Actualiser") { model.scan.selection = ids; model.refreshSelected() }.disabled(model.scan.isScanning)
            Button("Wake-on-LAN") { Task { await model.scan.runWakeOnLAN(for: ids) } }.disabled(host.mac == nil)
            Divider()
            Button("Copier l'adresse IP") { model.copy(host.ip, what: "Adresse") }
            if let name = host.displayName { Button("Copier le nom") { model.copy(name, what: "Nom") } }
            if let mac = host.mac { Button("Copier l'adresse MAC") { model.copy(mac, what: "Adresse MAC") } }
            Divider()
            Button("Retirer de la liste") { model.scan.deleteHosts(ids) }
        } else {
            Text(Format.count(hosts.count, "appareil sélectionné", "appareils sélectionnés"))
            Divider()
            Button("Analyser les ports…") { model.beginPortScan(ids: ids) }.disabled(model.scan.isScanning)
            Button("Actualiser") { model.scan.selection = ids; model.refreshSelected() }.disabled(model.scan.isScanning)
            Button("Wake-on-LAN") { Task { await model.scan.runWakeOnLAN(for: ids) } }.disabled(!hosts.contains { $0.mac != nil })
            Divider()
            Button("Copier les adresses IP") { model.scan.selection = ids; model.copySelectedIPs() }
            Divider()
            Button("Retirer de la liste") { model.scan.deleteHosts(ids) }
        }
    }
}
