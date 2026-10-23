Changelog
=========

The version is `VERSION` in `Scripts/bundle.sh` (and `AppVersion.defaultVersion`); each release is tagged `vX.Y.Z` in git.

0.9.0 — 2026-10-23
------------------

Première version numérotée, issue d'iPScanner 1.3.1 (Canberk Kılıçarslan, MIT).

- Scanner réseau natif macOS ultra-léger, paquet SwiftPM sans dépendance, dans la lignée visuelle de SimpleAudio et Simple Recorder ; interface en français.
- Découverte par socket ICMP datagramme (sans privilèges), table ARP du noyau pour les voisins qui ignorent le ping, repli TCP pour les plages routées : un /24 en une à deux secondes au lieu de 32 processus `ping`.
- Bonjour avec enregistrements TXT : modèle matériel, nom d'instance, 27 familles de services dont OSC, OSCQuery et NDI.
- Fiche de l'appareil : identité, type estimé avec ses indices, services, ports, ping en direct (sparkline), actions de connexion, Wake-on-LAN.
- Barre latérale : réseaux de ce Mac, favoris, filtres Bonjour et filtres rapides ; tri par colonne ; colonnes adaptées à la largeur.
- Scans `.simplescan`, comparaison (+ nouveaux, ~ modifiés, − disparus), exports CSV / JSON / IP:port / rapport texte, import de cibles, calculateur de sous-réseau, rescan automatique.
- Ligne de commande intégrée : `--scan`, `--self-test`, `--snapshot`, `--version`.
- Avertissement explicite quand macOS refuse l'accès au réseau local.
- Badges « Ce Mac » et « Passerelle », classifieur par indices pondérés sur 16 familles (switch / point d'accès, caméra, console, Linux, montre…) avec niveau de confiance et indices listés dans la fiche.
