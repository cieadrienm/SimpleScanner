import SimpleScannerCore
import SwiftUI

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart
        case profiles
        case device
        case memory
        case tools
        case limits

        var id: String { rawValue }
        var title: String {
            switch self {
            case .quickStart: L("Démarrage", "Getting Started")
            case .profiles: L("Profils et moteur", "Profiles & Engine")
            case .device: L("Fiche de l'appareil", "Device Inspector")
            case .memory: L("Noms, favoris, scans", "Labels, Favorites, Scans")
            case .tools: L("Ports, export, ligne de commande", "Ports, Export, CLI")
            case .limits: L("Autorisations et limites", "Permissions & Limits")
            }
        }
        var icon: String {
            switch self {
            case .quickStart: "play.circle"
            case .profiles: "dot.radiowaves.left.and.right"
            case .device: "person.text.rectangle"
            case .memory: "clock.arrow.2.circlepath"
            case .tools: "terminal"
            case .limits: "lock.shield"
            }
        }
    }

    @State private var selected: SectionID = .quickStart

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "book.closed").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent.swiftUI)
                Text(L("Guide d'utilisation — SimpleScanner", "User Guide — SimpleScanner")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textFaint.swiftUI)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.header.swiftUI)
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content(selected) }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.panel.swiftUI)
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            HStack {
                Button { close(); openShortcuts() } label: { Label(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"), systemImage: "command").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim.swiftUI)
                Spacer()
                Button(L("OK", "OK"), action: close).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.header.swiftUI)
        }
        .frame(width: 780, height: 540)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SectionID.allCases) { section in
                let isSelected = selected == section
                Button { selected = section } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(isSelected ? Theme.accent.swiftUI : Theme.textDim.swiftUI).frame(width: 16)
                        Text(section.title).font(.system(size: 12, weight: isSelected ? .semibold : .regular)).foregroundStyle(isSelected ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.laneSelected.swiftUI : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.background.swiftUI)
    }

    @ViewBuilder
    private func content(_ section: SectionID) -> some View {
        switch section {
        case .quickStart:
            title(L("Trois gestes", "Three Steps"))
            step("1", L("Choisir le réseau", "Pick a network"), L(
                "La barre haute propose les réseaux de ce Mac (Wi-Fi, Ethernet, VPN) et les favoris. Il est aussi possible de taper une adresse, un CIDR (192.168.1.0/24), une plage (10.0.0.1-10.0.0.50) ou plusieurs valeurs séparées par des virgules.",
                "The top bar lists this Mac’s networks (Wi-Fi, Ethernet, VPN) and saved favorites. You can also type an IP, a CIDR (192.168.1.0/24), a range (10.0.0.1-10.0.0.50), or multiple comma-separated targets."
            ))
            step("2", L("Scanner", "Scan"), L(
                "⌘R, ou Entrée dans le champ de plage. Les appareils apparaissent au fil des réponses, puis se complètent : nom, fabricant, services Bonjour.",
                "Press ⌘R, or Return in the range field. Devices appear as they reply and are progressively enriched with hostname, vendor, and Bonjour services."
            ))
            step("3", L("Ouvrir la fiche", "Inspect a device"), L(
                "Un clic sélectionne, un double-clic ouvre la fiche (⌥⌘I) : identité, services, ports, ping en direct et actions de connexion.",
                "Single-click selects, double-click opens the inspector (⌥⌘I): identity, services, ports, live ping, and connection actions."
            ))
            paragraph(L(
                "La première fois, macOS demande l'autorisation « Réseau local ». Sans elle, seul ce Mac et la passerelle répondent.",
                "On first launch, macOS asks for “Local Network” permission. Without it, only this Mac and the gateway can respond."
            ))
        case .profiles:
            title(L("Trois profils", "Three Profiles"))
            bullet(L("Rapide", "Fast"), L(
                "un ping ICMP par adresse, puis la table ARP du noyau. Le plus rapide : un /24 en une à deux secondes.",
                "one ICMP ping per address followed by the kernel ARP table. Fastest: a /24 in one to two seconds."
            ))
            bullet(L("Standard", "Standard"), L(
                "Rapide, plus NetBIOS (nom et groupe Windows) et un repli TCP pour les hôtes routés qui bloquent le ping. Recommandé.",
                "Fast, plus NetBIOS (Windows name and workgroup) and TCP fallback for routed hosts that block ping. Recommended."
            ))
            bullet(L("Approfondi", "Deep"), L(
                "Standard, puis analyse des ports courants et lecture des titres HTTP / bannières SSH sur chaque appareil trouvé.",
                "Standard, followed by common TCP port scanning and HTTP title / SSH banner grabbing on every discovered device."
            ))
            title(L("Comment ça marche", "How It Works"))
            paragraph(L(
                "SimpleScanner ouvre un seul socket ICMP (aucun privilège nécessaire sur macOS) et envoie une requête d'écho par adresse, espacée d'une milliseconde et demie pour laisser le noyau résoudre ARP. Les réponses donnent la latence et le TTL (indice de système). Puis la table ARP est lue : tout voisin qui existe y figure, même s'il ignore le ping. Les adresses hors des réseaux directs passent par un repli TCP sur quelques ports.",
                "SimpleScanner opens a single unprivileged ICMP socket on macOS and sends one echo request per address, paced 1.5 ms apart so the kernel can complete ARP resolution. Replies provide latency and TTL (OS hint). Next, the kernel ARP table is read: every local neighbor appears there even if it ignores ping. Addresses outside direct subnets use a TCP fallback across common ports."
            ))
            paragraph(L(
                "Le point de couleur : vert répond au ping, bleu présent via ARP seulement, cyan port TCP ouvert sans ping, gris sans réponse.",
                "Status dot colors: green replies to ping, blue present via ARP only, cyan open TCP port without ping, gray no response."
            ))
            paragraph(L(
                "Bonjour est écouté en permanence : AirPlay, HomeKit, SMB, SSH, IPP, Chromecast, OSC, NDI… Les enregistrements TXT livrent souvent le modèle exact (MacBookPro18,1, AppleTV14,1).",
                "Bonjour runs continuously: AirPlay, HomeKit, SMB, SSH, IPP, Chromecast, OSC, NDI… TXT records often reveal the exact hardware model (MacBookPro18,1, AppleTV14,1)."
            ))
        case .device:
            title(L("Ce que montre la fiche", "What the Inspector Shows"))
            bullet(L("Identité", "Identity"), L(
                "nom DNS, NetBIOS, Bonjour, modèle, adresse MAC et fabricant (registre IEEE embarqué), latence, TTL.",
                "DNS, NetBIOS, Bonjour name, hardware model, MAC address and vendor (bundled IEEE registry), latency, TTL."
            ))
            bullet(L("Ce Mac, Passerelle", "This Mac, Gateway"), L(
                "deux badges sûrs : l'adresse de ce Mac (avec son modèle) et la passerelle par défaut du réseau.",
                "two authoritative badges: this Mac’s address (with model) and the network’s default gateway."
            ))
            bullet(L("Type estimé", "Estimated Type"), L(
                "routeur / box, switch / point d'accès, Mac, PC Windows, Linux / Raspberry, téléphone / tablette, montre, TV / boîtier vidéo, enceinte, caméra, console, imprimante, NAS, serveur, objet connecté. Chaque indice (nom, fabricant, modèle Bonjour, ports, TTL, services) pèse un poids ; la famille en tête doit valoir le double de la suivante, sinon le type reste inconnu. « Probable » signale un seul indice faible, l'icône est alors estompée. Les indices sont listés sous l'identité.",
                "router / gateway, switch / access point, Mac, Windows PC, Linux / Raspberry, phone / tablet, watch, TV / media player, speaker, camera, console, printer, NAS, server, smart device. Each clue (hostname, vendor, Bonjour model, ports, TTL, services) carries a weight; the top category must score at least twice the runner-up or the type stays unknown. “Likely” marks a single weak clue with a dimmed icon. Clues are listed under Identity."
            ))
            bullet(L("Services Bonjour", "Bonjour Services"), L(
                "chaque instance publiée par l'appareil, avec son nom. Une puce cliquable ouvre la connexion : SSH ou SFTP dans Terminal, Partage d'écran, SMB ou AFP dans le Finder, HTTP/HTTPS et OSCQuery dans le navigateur sur le bon port.",
                "every service instance advertised by the device, with its name. Clicking a chip opens the connection: SSH or SFTP in Terminal, Screen Sharing, SMB or AFP in Finder, HTTP/HTTPS and OSCQuery in your browser on the advertised port."
            ))
            bullet(L("Ports ouverts", "Open Ports"), L(
                "ceux de la dernière analyse, avec le service habituel ; les puces des ports connus (22, 80, 443, 445, 548, 5900, 3389, 8080, 5000…) s'ouvrent de même. « Analyser… » lance une analyse ciblée.",
                "ports found during the last scan with their standard service name; known port chips (22, 80, 443, 445, 548, 5900, 3389, 8080, 5000…) also open on click. “Scan…” runs a targeted port scan."
            ))
            bullet(L("Ping en direct", "Live Ping"), L(
                "une requête par seconde pendant que la fiche est ouverte : courbe, moyenne, min, max, perte.",
                "one echo request per second while the inspector is open: sparkline, average, min, max, packet loss."
            ))
            bullet(L("Actions", "Actions"), L(
                "HTTP, HTTPS, SSH, Partage d'écran, SMB, AFP, Bureau à distance, Telnet, ping dans Terminal, Wake-on-LAN. Les actions en orange correspondent à un port ou un service vu.",
                "HTTP, HTTPS, SSH, Screen Sharing, SMB, AFP, Remote Desktop, Telnet, ping in Terminal, Wake-on-LAN. Highlighted actions match a detected open port or Bonjour service."
            ))
        case .memory:
            title(L("Nommer", "Labeling"))
            paragraph(L(
                "Le champ Nom de la fiche (ou ⏎ sur la ligne) attache une étiquette à l'adresse MAC : elle suit l'appareil quand son IP change. Un #tag dans le nom sert de mot-clé à la recherche ; le filtre « Appareils nommés » ne garde que les étiquetés.",
                "The Label field in the inspector (or ⏎ on a selected row) binds a custom name to the MAC address so it follows the device even if its IP changes. A #tag in the label is searchable, and the “Labeled devices” filter shows only labeled hosts."
            ))
            title(L("Favoris", "Favorites"))
            paragraph(L(
                "☆ garde la plage courante. Les favoris se renomment par clic droit dans la barre latérale et se retrouvent dans le menu Réseau.",
                "Click ☆ to save the current target range. Right-click a favorite in the sidebar to rename it; favorites are also available in the Network menu."
            ))
            title(L("Scans enregistrés et comparaison", "Saved Scans & Comparison"))
            paragraph(L(
                "⌘S enregistre le scan (.simplescan, du JSON lisible). ⌘O le rouvre sans toucher au réseau. ⇧⌘O compare le scan courant à un scan enregistré : + nouveau, ~ modifié (nom, MAC, fabricant, ports, service), − disparu, avec le détail dans la barre d'état. Les fichiers .ipscan.json d'iPScanner s'ouvrent aussi.",
                "⌘S saves the scan (.simplescan human-readable JSON). ⌘O reopens it offline. ⇧⌘O compares the current scan against a saved scan: + new, ~ changed (name, MAC, vendor, ports, service), − gone, with full details in the status bar. Legacy .ipscan.json files also open."
            ))
            title(L("Rescan automatique", "Auto-rescan"))
            paragraph(L(
                "Menu Outils ou Préférences : 30 s à 15 min après la fin du scan précédent, pour surveiller un réseau de plateau.",
                "Tools menu or Preferences: rescan 30s to 15m after the previous scan finishes—ideal for monitoring a stage or studio network."
            ))
        case .tools:
            title(L("Analyse de ports", "Port Scanning"))
            paragraph(L(
                "⌘P sur la sélection : préréglages Courants, Web, 1–1024, ou liste personnalisée (22, 80, 8000-8100). Les connexions sont des connexions TCP ordinaires, six appareils à la fois. Option : lire les titres HTTP et bannières SSH.",
                "Press ⌘P on the selection: Common, Web, 1–1024 presets, or a custom list (22, 80, 8000-8100). Uses standard unprivileged TCP connections across six devices at a time. Optional: read HTTP titles and SSH banners."
            ))
            title(L("Export", "Export"))
            paragraph(L(
                "⌘E : CSV, JSON, liste ip:port (pour Nmap ou un pare-feu) ou rapport texte. Lignes affichées ou tous les appareils, vers un fichier ou le presse-papiers.",
                "Press ⌘E: CSV, JSON, ip:port list (for Nmap or firewall rules), or text report. Export visible rows or all alive devices to a file or the clipboard."
            ))
            title(L("Calculateur de sous-réseau", "Subnet Calculator"))
            paragraph(L(
                "Menu Outils : un CIDR donne réseau, diffusion, plage d'hôtes, masque et wildcard, et peut devenir la plage à scanner.",
                "Tools menu: enter a CIDR to compute network, broadcast, usable host range, netmask, and wildcard mask, or apply it directly as the scan range."
            ))
            title(L("Ligne de commande", "Command Line"))
            code("SimpleScanner --scan 192.168.1.0/24 --profile standard --format json")
            code("SimpleScanner --scan --input cibles.txt --ports 22,80,443 --format csv --output scan.csv")
            paragraph(L(
                "Depuis le bundle : /Applications/SimpleScanner.app/Contents/MacOS/SimpleScanner. Aussi --self-test, --snapshot image.png, --lang fr|en et --version.",
                "From the app bundle: /Applications/SimpleScanner.app/Contents/MacOS/SimpleScanner. Also supports --self-test, --snapshot image.png, --lang fr|en, and --version."
            ))
        case .limits:
            title(L("Autorisation Réseau local", "Local Network Permission"))
            paragraph(L(
                "macOS demande une fois l'accès au réseau local. S'il est refusé, les paquets vers les voisins sont rejetés (« No route to host ») et le scan ne voit que ce Mac et la passerelle : l'avertissement le signale. Réglages Système › Confidentialité et sécurité › Réseau local.",
                "macOS prompts once for Local Network access. If denied, packets to local neighbors are rejected (“No route to host”) and scans only see this Mac and the gateway—an orange warning badge alerts you. Enable it in System Settings › Privacy & Security › Local Network."
            ))
            title(L("Ce que les résultats veulent dire", "What Results Mean"))
            bullet(L("Sans réponse", "No response"), L(
                "ne prouve pas l'absence : un appareil peut bloquer le ping et ne rien publier. Sur un réseau direct, l'absence d'entrée ARP est en revanche un signe fort.",
                "does not prove absence: a device may block ping and advertise nothing. On a local subnet, however, having no ARP entry is a strong sign the address is unused."
            ))
            bullet(L("Adresse MAC", "MAC Address"), L(
                "connue seulement pour les voisins directs ; derrière un routeur, non. Les adresses privées (iPhone, iPad, Android récents) ne révèlent pas le fabricant.",
                "available only for direct local-link neighbors, never across routers. Randomized private MAC addresses (modern iPhone, iPad, Android) do not reveal a vendor."
            ))
            bullet(L("Type estimé", "Estimated Type"), L(
                "une estimation ; les indices sont affichés.",
                "a heuristic estimate; supporting clues are always shown."
            ))
            bullet(L("Wake-on-LAN", "Wake-on-LAN"), L(
                "le paquet est envoyé en diffusion sur le port 9 ; rien ne confirme le réveil.",
                "sends a broadcast magic packet on UDP port 9; the protocol provides no wake confirmation."
            ))
            bullet(L("Plages", "Ranges"), L(
                "65 536 adresses au plus par scan. Les grandes plages sont envoyées plus vite, puis le repli TCP peut prendre du temps : ⌘. arrête tout.",
                "up to 65,536 addresses per scan. Larger ranges use faster ping pacing, though TCP fallback can still take time—press ⌘. to stop at any point."
            ))
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text.swiftUI).padding(.top, 4)
    }
    private func paragraph(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
    }
    private func bullet(_ term: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(Theme.accent.swiftUI)
            (Text(term + " — ").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text.swiftUI) + Text(text).font(.system(size: 12)).foregroundStyle(Theme.textDim.swiftUI))
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        }
    }
    private func step(_ number: String, _ heading: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Theme.background.swiftUI)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.accent.swiftUI))
            VStack(alignment: .leading, spacing: 3) {
                Text(heading).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textDim.swiftUI).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
        }
    }
    private func code(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text.swiftUI).textSelection(.enabled)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.3)))
    }
}
