# SimpleScanner

Scanner réseau natif, ultra-léger (~5 Mo, aucune dépendance) et rapide pour macOS, conçu dans le même esprit que **SimpleAudio**, **SimpleMIDIPlayer** et **Simple Recorder** (**cie Adrien M**). Issu d'[iPScanner](https://github.com/canberkys/iPScanner) de Canberk Kılıçarslan (MIT), réécrit autour d'un moteur ICMP natif et de l'interface sombre de la famille.

## Fonctionnalités

- **Découverte en une à deux secondes par /24** : un socket ICMP datagramme (sans privilèges), une requête d'écho par adresse espacée d'1,5 ms, puis la table ARP du noyau pour les voisins qui ignorent le ping, et un repli TCP (445, 80, 443, 22, 3389, 62078) pour les plages routées. Latence et TTL par appareil. Trois profils : **Rapide** (ICMP + ARP), **Standard** (+ NetBIOS, repli TCP), **Approfondi** (+ ports courants et bannières).
- **Qui est qui** : nom DNS inverse (`.local` compris), nom NetBIOS et groupe de travail, nom d'instance Bonjour, modèle matériel lu dans les enregistrements TXT (`MacStudio13,1`, `AppleTV14,1`, `iPhone16,1`), fabricant par le registre IEEE embarqué (MA-L, MA-M, MA-S), type d'appareil estimé (routeur, Mac, téléphone, TV, enceinte, imprimante, NAS, Windows, objet connecté) avec ses indices.
- **Bonjour en continu** : 27 familles de services dont AirPlay, HomeKit, Chromecast, SMB, SSH, IPP, Sonos, Hue, **OSC**, **OSCQuery** et **NDI** ; la barre latérale filtre la liste par service.
- **Fiche de l'appareil** : identité, services, ports ouverts avec leur service, **ping en direct** (sparkline, moyenne, min, max, perte), actions en un clic (HTTP, HTTPS, SSH, Partage d'écran, SMB, AFP, Bureau à distance, Telnet, ping dans Terminal, Wake-on-LAN), copie de l'IP et de la MAC.
- **Mémoire du réseau** : noms persistants attachés à l'adresse MAC (avec `#tags` cherchables), favoris, scans enregistrés (`.simplescan`, JSON lisible) et **comparaison** d'un scan à un autre (`+` nouveaux, `~` modifiés, `−` disparus), rescan automatique (30 s à 15 min).
- **Outils** : analyse de ports par préréglages (Courants, Web, 1–1024) ou liste libre avec lecture des bannières, import d'une liste de cibles (`.txt` / `.csv`), calculateur de sous-réseau, exports **CSV**, **JSON**, **liste `ip:port`** et **rapport texte**.
- **Interface** : liste triable aux colonnes adaptées à la largeur, lignes animées au fil des réponses, recherche instantanée avec surlignage, barre latérale et fiche escamotables, fenêtres natives À propos, Aide (`⌘?`) et Raccourcis (`⌘/`), tout en français.
- **Ligne de commande intégrée** au même exécutable : `--scan`, `--self-test`, `--snapshot`, `--version`.

## Compilation & Installation

```bash
# Générer l'icône et assembler /Applications/SimpleScanner.app
Scripts/bundle.sh release

# Construire build/SimpleScanner.app sans l'installer
Scripts/bundle.sh debug

# Suite de tests (loopback uniquement, aucun paquet vers le réseau)
swift test

# Auto-test de bout en bout et capture PNG du réseau de démonstration, sans interaction
.build/debug/SimpleScanner --self-test
.build/debug/SimpleScanner --snapshot /tmp/simplescanner.png
```

Requiert Xcode 16 ou plus récent ; l'app tourne sur macOS 15 et plus. À son premier scan, macOS demande l'autorisation **Réseau local** ; sans elle, seuls ce Mac et la passerelle répondent et l'app l'indique.

## Ligne de commande

```bash
/Applications/SimpleScanner.app/Contents/MacOS/SimpleScanner --scan 192.168.1.0/24 --profile standard --format txt
/Applications/SimpleScanner.app/Contents/MacOS/SimpleScanner --scan --input cibles.txt --ports 22,80,443 --banners --format csv --output scan.csv
```

Options : `--profile quick|standard|deep`, `--ports <liste>`, `--banners`, `--format json|csv|txt|ip-port`, `--output <chemin>`, `--quiet`. Codes de sortie : `0` succès, `1` argument invalide, `2` erreur d'exécution.

## Ce que les résultats veulent dire

- **Sans réponse** ne prouve pas l'absence : un appareil peut bloquer le ping et ne rien publier. Sur votre réseau direct, l'absence d'entrée ARP est en revanche un signe fort.
- L'**adresse MAC** n'est connue que des voisins directs ; les adresses privées (iPhone, iPad, Android récents) ne révèlent pas le fabricant.
- Le **type d'appareil** est une estimation ; les indices sont affichés dans la fiche.
- **Wake-on-LAN** envoie le paquet magique en diffusion sur le port 9 ; rien ne confirme le réveil.
- Au plus **65 536 adresses** par scan. Le noyau macOS rejette 20 s durant toute adresse dont la résolution ARP a échoué : un second scan immédiat sur un réseau calme signale ces rejets, c'est normal.

## Confidentialité

Aucune télémétrie, aucun compte, aucune connexion sortante hors de votre réseau. Le registre des fabricants ([IEEE](https://standards-oui.ieee.org/)) est embarqué ; `Scripts/build-vendor-db.py` le régénère depuis `data/ieee`.

## Crédits

**cie Adrien M** (Compagnie Adrien M) — Bundle ID : `net.cieadrienm.simplescanner`. Dérivé d'iPScanner © Canberk Kılıçarslan, licence MIT ([LICENSE](LICENSE)).
