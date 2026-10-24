# Instructions Agent — SimpleScanner

## Identité & Crédits
- Compagnie : **cie Adrien M** (ou **Compagnie Adrien M**), Adrien Mondot. Adrien (spectacle vivant) est l'unique utilisateur ; il parle français.
- Identifiant de bundle : `net.cieadrienm.simplescanner`. Famille : SimpleAudio, SimpleMIDIPlayer, SimpleRecorder (même palette, mêmes composants, mêmes scripts).
- Origine : fork d'[iPScanner](https://github.com/canberkys/iPScanner) de Canberk Kılıçarslan (MIT). Depuis le 24 octobre 2026 : licence GPL 3.0 ou ultérieure (`LICENSE`), la notice MIT d'origine est dans `LICENSE-iPScanner`. Le dossier local s'appelle toujours `iPScanner/`. Remotes : `origin` = github.com/cieadrienm/SimpleScanner (public) + Gitea `amcb/SimpleScanner` ; `upstream` = le dépôt d'origine de Canberk, **ne jamais y pousser**.

## Lire d'abord
- `DECISIONS.md` — D1…, le pourquoi de chaque choix, et ce qui est remis à plus tard. **Ajouter une entrée pour tout choix structurant.**
- `README.md` — fonctionnalités, ligne de commande, limites.

## Architecture
- `Sources/SimpleScannerCore` : tout ce qui n'a pas besoin de la fenêtre. Modèle (`Host`, `ScanRange`/`IPv4`, `MACAddress`, `ScanEvent`, `ScanProfile`, `ScanSnapshot`, `SnapshotDiff`), registre IEEE embarqué (`OUILookup` + `Resources/vendors.json`, 1,8 Mo), `DeviceClassifier`, export (`ExportService`), et le moteur réseau : `ICMPPinger` (un socket ICMP datagramme, sans privilèges), `NetworkScanner` (découverte ICMP → ARP → repli TCP, puis DNS/NetBIOS), `ARPLookup` (`arp -an`), `NetworkInterface`, `DNSResolver`, `NetBIOSResolver`, `PortScanner`, `BannerProbe`, `WakeOnLAN`. Aucune dépendance UI, aucun paquet tiers.
- `Sources/SimpleScanner` : l'app SwiftUI. `ScanController` (le scan : cibles, cycle, résultats, étiquettes, favoris, filtres, comparaison ; `Operations` injectables pour les tests), `MDNSDiscovery` (Bonjour avec TXT `model=`), `AppModel` (panneaux, feuilles, tri, fichiers), `Theme`/`Components` (palette et contrôles de la famille), `Views/`, `HeadlessScan` (`--scan`), `SelfTest`, `Snapshot`, `SyntheticScan` (réseau de démonstration, zéro paquet).
- Invariants : la fenêtre ne porte aucun état du scan, elle montre `ScanController` ; le cœur n'importe ni AppKit ni SwiftUI ; tout nouveau comportement a un test.

## Vérification
- Toujours valider par `swift test` (≈ 170 tests, loopback seulement), `.build/debug/SimpleScanner --self-test` et `.build/debug/SimpleScanner --snapshot /tmp/simplescanner.png` (rendu hors écran du réseau de démonstration : c'est l'œil de l'agent, Adrien ne donne pas l'accès à l'écran).
- Scan réel : `.build/debug/SimpleScanner --scan 192.168.0.0/24 --format txt`. **Le réseau local est erratique depuis un processus non autorisé** (règle macOS « Réseau local ») : ne tester que depuis l'app signée de `build/`, ou depuis un Terminal qu'Adrien a autorisé. `/sbin/ping` et `arp`, binaires système, y échappent et servent de vérité terrain.
- Pour mettre à jour `/Applications/SimpleScanner.app`, exécuter `Scripts/bundle.sh release` ; `Scripts/bundle.sh debug` construit `build/SimpleScanner.app` sans l'installer.
- Version : `VERSION` dans `Scripts/bundle.sh` et `AppVersion.defaultVersion`, changées ensemble (correctif : x.y.Z ; fonction : x.Y.0), avec une ligne dans `CHANGELOG.md` et un tag git `vX.Y.Z` quand Adrien déploie.

## Règles qui ont coûté cher
- **Ne jamais relancer une adresse rejetée par le noyau** (`EHOSTUNREACH`) : macOS marque un voisin « down » 20 s après un échec ARP, et compte les tentatives par seconde ; la seconde passe ne concerne que les hôtes résolus.
- **Espacer les échos ICMP** (1,5 ms sur un /24) : en rafale, le tampon d'émission sature (`EAGAIN`) dès 16 résolutions ARP en attente sur Wi-Fi.
- **Une `List` SwiftUI (NSTableView) ne dessine pas ses lignes hors écran** : la liste des appareils est un `ScrollView` + `LazyVStack` avec sélection, clavier et menu contextuel gérés à la main (D7).
- Répondre en français ; code, commentaires et commits en anglais, avec la ligne `Co-Authored-By` de l'harnais.
