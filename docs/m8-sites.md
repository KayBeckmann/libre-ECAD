# M8 – mehrsprachige Homepage und Wiki

Stand 25.10.2026: **Entwicklungsumfang für die private LAN-Vorschau umgesetzt und
technisch abgenommen.** Öffentlicher Livegang, tatsächliche Rechtstexte sowie
Produktname-/Marken-/Domainfreigabe bleiben Kays Entscheidung. Offene fachliche,
Geräte- und HA-Abnahmen aus M6/M7 werden dadurch nicht als erledigt markiert.

## Ergebnis

- Homepage und Wiki als zwei unabhängige statische nginx-Container; getrennt vom
  App-Stack über `compose.sites.yml`. Standardbindung nur Loopback; für diese
  autorisierte LAN-Vorschau ist in der ignorierten `.sites.env` die konkrete
  Adresse `10.10.2.123` konfiguriert.
- Homepage: `http://10.10.2.123:8187/de/`, Wiki:
  `http://10.10.2.123:8188/de/m8-dev/start/`. Beide bieten Englisch. Die Adressen
  gelten für diesen Entwicklungsrechner, nicht als öffentliche Domains.
- Gestaltung in Petrol/Gold entsprechend der vorhandenen Werkbank/Mockups.
  Synthetischer Dreiphasenplan aus dem tatsächlichen SVG-Renderer, lokale Fonts,
  zugängliche Navigation und responsive Darstellung.
- Homepage unterscheidet verfügbare Entwicklungsfunktionen, Self-Hosting,
  vorbereiteten Dienstleisterbetrieb und ein noch nicht veröffentlichtes
  Managed-Mietangebot. Keine erfundenen Preise, SLA oder Buchungsformulare.
- Elf Wiki-Kapitel je Sprache: Start/Version, Installation/Compose,
  Backup/Wiederherstellung, Rollen/Firmengrenzen, Backendwechsel, Artikelquellen,
  Zeichnen/Planen, Offline, API/MCP, Betrieb/Veröffentlichung, Fehlersuche.
- Versionspfade `/de/m8-dev/...` und `/en/m8-dev/...`; stabile Kapitel-/Abschnitts-IDs,
  Sprachwechsel erhält Kapitel und Anker. Lokale Suche je Sprache und Version.
  DE/EN-Pflege und Veröffentlichungsreview verantwortet Kay Beckmann. Der Generator
  prüft Paarigkeit und Verweise; semantische Übersetzungsprüfung bleibt Review.
- Die Sprachwahl betrifft diese Seiten, nicht eine behauptete vollständige
  Übersetzung der App. Historische Meilensteindokumente bleiben historische Notizen.

## Download und Quellbezug

Die Dokumentation und der Linux-Download beziehen sich auf den App-Quellstand
`37603fae40b841bb25b19859a62a2d9f3dc4f629`. Die folgenden M8-Commits verändern die
Informationsseiten und deren Prüfwerkzeuge, nicht das App-Bundle.

Linux x86_64, Entwicklungsartefakt:
`libre-ecad-linux-x64-37603fa.tar.gz`, 15.304.188 Bytes.
SHA-256: `67acec37feb53c0a8a5ddd2f59d8c993d4ee404e7a7b26c0ccf3201a9fb1d8fd`.
Das Paket enthält das gesamte Release-Bundle und die MIT-Lizenz. Manifest,
Prüfprotokoll und SHA256SUMS stehen neben dem Download bereit. Lokale Artefakte
werden nicht ins Git-Repository aufgenommen. Ein erneuter Build kann andere
Archivbytes erzeugen; maßgeblich ist dann das neu geprüfte Manifest.

`sites/verify_linux.py` verweigert abweichende App-Quellen, entfernt alte
Erfolgsmanifeste vor dem Prüfen und erstellt erst nach erfolgreichen Prüfungen
ein Paket. Fehlendes Manifest erzeugt keinen Link; unpassende Hashes, Quellstände
oder Prüfnachweise brechen den Seiten-Build ab. Ein Neuaufbau ohne Manifest entfernt
auch zuvor ausgelieferte Downloads. Das lokale Manifest ist ein überprüfbarer
Betreibernachweis, keine kryptografisch signierte Lieferketten-Attestierung.

Die Linux-Prüfung gilt für den dokumentierten Host unter virtuellem Display,
nicht pauschal für alle Distributionen. Android-Build vorhanden, Release aktuell
mit Debug-Schlüssel und HTTPS-Pflicht; Geräteabnahme offen. Windows-Build/-Gerät
offen. Daher für diese Plattformen kein Download-Link.

## Reproduzierbare Abnahme

Vom Repository-Root aus:

```bash
python3 -m unittest discover -s sites/tests -v
python3 sites/verify_linux.py --xvfb /absolute/path/to/Xvfb
python3 sites/build.py
docker compose -p libre-ecad-sites --env-file .sites.env -f compose.sites.yml up -d --build
python3 scripts/browser-m8.py --homepage http://10.10.2.123:8187 --wiki http://10.10.2.123:8188
python3 scripts/smoke-m8-runbook.py
python3 scripts/smoke-m8-sites.py --homepage http://10.10.2.123:8187 --wiki http://10.10.2.123:8188
```

`--xvfb` ist nur nötig, falls Xvfb nicht im PATH liegt. Browserprüfung benötigt
Python Playwright und dessen Chromium. IPs an die jeweilige private Umgebung
anpassen. Der Ausfalltest stoppt kurz jeweils **einen Informationsseiten-Container**
und startet ihn in `finally` wieder; er benötigt beide gestarteten Seiten.
Der Runbook-Test verwendet einen zufällig benannten, isolierten Compose-Stack
mit ausschließlich synthetischen Daten und entfernt nur dessen Testvolumes.

Tatsächlich ausgeführt:

- 13 Generatorprüfungen: DE/EN-Paarigkeit, Kapitel-/Ankerverweise, HTML-Escaping,
  Origin-Validierung, fehlender Download, Entfernen alter Artefakte, Hash-/Log-
  Manipulation, fehlende Prüfschritte und falscher App-Quellstand.
- Flutter-Analyse ohne Befund, 15 Unit-/Widgettests und nativer Linux-Integrationstest
  erfolgreich. Echte verschlüsselte Datei, Wiederöffnen, Editor und PDF bei
  blockiertem Dart-HTTP; danach Release-Build und tatsächliches Release-Fenster.
  Eigene temporäre XDG-Daten-/Konfigurationsverzeichnisse, kein echter Benutzervault.
- Dart-Analyse des Dokumentpakets einschließlich neuem SVG-Beispiel ohne Befund.
- Beide Container gebaut und gesund; Build-Kontext begrenzt auch mit dem lokalen
  klassischen Docker-Builder. Geheimnisse/App-Buildverzeichnisse ausgeschlossen.
- HTTP-Crawl: 28 HTML-Seiten, insgesamt 41 Ressourcen und 34 Ankerverweise korrekt.
  CSP, nosniff und noindex für Seiten und Assets vorhanden.
- Chromium: DE/EN, Suchtreffer/kein Treffer/Leeren, Sprachwechsel mit wechselndem
  Anker, Tastatur-Einstieg und mobiles Kapitelmenü, alle Seiten bei 390 Pixel ohne
  horizontalen Seitenüberlauf, Desktopansichten visuell geprüft. Navigation mit
  festen Origins auch ohne JavaScript, einschließlich mobiler Kapitelübersicht.
- Echter Download beider Sprachseiten stimmt mit dem Manifest überein. Keine
  Browserfehler, externen Ressourcenanfragen, Cookies oder Browserablage.
- Runbook: Custom-Format-Dump, Inhaltsliste, Restore und Datenvergleich für alle
  drei Datenbankdienste; Archivvolume per tar exportiert, entfernt, zurückgespielt
  und bytegenau verglichen. Kein Eingriff in bestehende Firmen-/Projektdaten.
- Unabhängiger Betrieb: bei gestopptem Wiki bleibt die Homepage erreichbar und
  umgekehrt; beide Container anschließend wieder verfügbar.

Beim Prüfen gefundene Fehler wurden korrigiert: Docker-Kontext bei klassischem
Builder, lange deutsche Überschriften auf schmalen Displays, Sprachanker nach
Hashwechsel und mobile Kapitelnavigation ohne JavaScript.

Pflege, Build-Details und Veröffentlichungstor: [sites/README.md](../sites/README.md).
