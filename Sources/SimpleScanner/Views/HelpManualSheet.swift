import SwiftUI

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart = "Démarrage"
        case profiles = "Profils et moteur"
        case device = "Fiche de l'appareil"
        case memory = "Noms, favoris, scans"
        case tools = "Ports, export, ligne de commande"
        case limits = "Autorisations et limites"

        var id: String { rawValue }
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
                Text("Guide d'utilisation — SimpleScanner").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.swiftUI)
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
                Button { close(); openShortcuts() } label: { Label("Raccourcis clavier (⌘/)", systemImage: "command").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim.swiftUI)
                Spacer()
                Button("OK", action: close).keyboardShortcut(.defaultAction)
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
                        Text(section.rawValue).font(.system(size: 12, weight: isSelected ? .semibold : .regular)).foregroundStyle(isSelected ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.laneSelected.swiftUI : Color.clear))
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
            title("Trois gestes")
            step("1", "Choisissez le réseau", "La barre haute propose les réseaux de ce Mac (Wi-Fi, Ethernet, VPN) et vos favoris. Vous pouvez aussi taper une adresse, un CIDR (192.168.1.0/24), une plage (10.0.0.1-10.0.0.50) ou plusieurs valeurs séparées par des virgules.")
            step("2", "Scanner", "⌘R, ou Entrée dans le champ de plage. Les appareils apparaissent au fil des réponses, puis se complètent : nom, fabricant, services Bonjour.")
            step("3", "Regardez la fiche", "Un clic sélectionne, un double-clic ouvre la fiche (⌥⌘I) : identité, services, ports, ping en direct et actions de connexion.")
            paragraph("La première fois, macOS demande l'autorisation « Réseau local ». Sans elle, seul ce Mac et la passerelle répondent.")
        case .profiles:
            title("Trois profils")
            bullet("Rapide", "un ping ICMP par adresse, puis la table ARP du noyau. Le plus rapide : un /24 en une à deux secondes.")
            bullet("Standard", "Rapide, plus NetBIOS (nom et groupe Windows) et un repli TCP pour les hôtes routés qui bloquent le ping. Recommandé.")
            bullet("Approfondi", "Standard, puis analyse des ports courants et lecture des titres HTTP / bannières SSH sur chaque appareil trouvé.")
            title("Comment ça marche")
            paragraph("SimpleScanner ouvre un seul socket ICMP (aucun privilège nécessaire sur macOS) et envoie une requête d'écho par adresse, espacée d'une milliseconde et demie pour laisser le noyau résoudre ARP. Les réponses donnent la latence et le TTL (indice de système). Puis la table ARP est lue : tout voisin qui existe y figure, même s'il ignore le ping. Les adresses hors de vos réseaux directs passent par un repli TCP sur quelques ports.")
            paragraph("Le point de couleur : vert répond au ping, bleu présent via ARP seulement, cyan port TCP ouvert sans ping, gris sans réponse.")
            paragraph("Bonjour est écouté en permanence : AirPlay, HomeKit, SMB, SSH, IPP, Chromecast, OSC, NDI… Les enregistrements TXT livrent souvent le modèle exact (MacBookPro18,1, AppleTV14,1).")
        case .device:
            title("Ce que montre la fiche")
            bullet("Identité", "nom DNS, NetBIOS, Bonjour, modèle, adresse MAC et fabricant (registre IEEE embarqué), latence, TTL.")
            bullet("Ce Mac, Passerelle", "deux badges sûrs : l'adresse de ce Mac (avec son modèle) et la passerelle par défaut du réseau.")
            bullet("Type estimé", "routeur / box, switch / point d'accès, Mac, PC Windows, Linux / Raspberry, téléphone / tablette, montre, TV / boîtier vidéo, enceinte, caméra, console, imprimante, NAS, serveur, objet connecté. Chaque indice (nom, fabricant, modèle Bonjour, ports, TTL, services) pèse un poids ; la famille en tête doit valoir le double de la suivante, sinon le type reste inconnu. « Probable » signale un seul indice faible, l'icône est alors estompée. Les indices sont listés sous l'identité.")
            bullet("Services Bonjour", "chaque instance publiée par l'appareil, avec son nom.")
            bullet("Ports ouverts", "ceux de la dernière analyse, avec le service habituel. « Analyser… » lance une analyse ciblée.")
            bullet("Ping en direct", "une requête par seconde pendant que la fiche est ouverte : courbe, moyenne, min, max, perte.")
            bullet("Actions", "HTTP, HTTPS, SSH, Partage d'écran, SMB, AFP, Bureau à distance, Telnet, ping dans Terminal, Wake-on-LAN. Les actions en orange correspondent à un port ou un service vu.")
        case .memory:
            title("Nommer")
            paragraph("Le champ Nom de la fiche (ou ⏎ sur la ligne) attache une étiquette à l'adresse MAC : elle suit l'appareil quand son IP change. Un #tag dans le nom sert de mot-clé à la recherche ; le filtre « Appareils nommés » ne garde que les étiquetés.")
            title("Favoris")
            paragraph("☆ garde la plage courante. Les favoris se renomment par clic droit dans la barre latérale et se retrouvent dans le menu Réseau.")
            title("Scans enregistrés et comparaison")
            paragraph("⌘S enregistre le scan (.simplescan, du JSON lisible). ⌘O le rouvre sans toucher au réseau. ⇧⌘O compare le scan courant à un scan enregistré : + nouveau, ~ modifié (nom, MAC, fabricant, ports, service), − disparu, avec le détail dans la barre d'état. Les fichiers .ipscan.json d'iPScanner s'ouvrent aussi.")
            title("Rescan automatique")
            paragraph("Menu Outils ou Préférences : 30 s à 15 min après la fin du scan précédent, pour surveiller un réseau de plateau.")
        case .tools:
            title("Analyse de ports")
            paragraph("⌘P sur la sélection : préréglages Courants, Web, 1–1024, ou votre liste (22, 80, 8000-8100). Les connexions sont des connexions TCP ordinaires, six appareils à la fois. Option : lire les titres HTTP et bannières SSH.")
            title("Export")
            paragraph("⌘E : CSV, JSON, liste ip:port (pour Nmap ou un pare-feu) ou rapport texte. Lignes affichées ou tous les appareils, vers un fichier ou le presse-papiers.")
            title("Calculateur de sous-réseau")
            paragraph("Menu Outils : un CIDR donne réseau, diffusion, plage d'hôtes, masque et wildcard, et peut devenir la plage à scanner.")
            title("Ligne de commande")
            code("SimpleScanner --scan 192.168.1.0/24 --profile standard --format json")
            code("SimpleScanner --scan --input cibles.txt --ports 22,80,443 --format csv --output scan.csv")
            paragraph("Depuis le bundle : /Applications/SimpleScanner.app/Contents/MacOS/SimpleScanner. Aussi --self-test, --snapshot image.png et --version.")
        case .limits:
            title("Autorisation Réseau local")
            paragraph("macOS demande une fois l'accès au réseau local. S'il est refusé, les paquets vers vos voisins sont rejetés (« No route to host ») et le scan ne voit que ce Mac et la passerelle : l'avertissement le signale. Réglages Système › Confidentialité et sécurité › Réseau local.")
            title("Ce que les résultats veulent dire")
            bullet("Sans réponse", "ne prouve pas l'absence : un appareil peut bloquer le ping et ne rien publier. Sur votre réseau direct, l'absence d'entrée ARP est en revanche un signe fort.")
            bullet("Adresse MAC", "connue seulement pour vos voisins directs ; derrière un routeur, non. Les adresses privées (iPhone, iPad, Android récents) ne révèlent pas le fabricant.")
            bullet("Type estimé", "une estimation ; les indices sont affichés.")
            bullet("Wake-on-LAN", "le paquet est envoyé en diffusion sur le port 9 ; rien ne confirme le réveil.")
            bullet("Plages", "65 536 adresses au plus par scan. Les grandes plages sont envoyées plus vite, puis le repli TCP peut prendre du temps : ⌘. arrête tout.")
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
