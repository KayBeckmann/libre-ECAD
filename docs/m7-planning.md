# M7 – Planarten, Makros, Berechnungen und Materialübergabe

Entwicklungsumfang für die private LAN-Vorschau. Die fachliche Modellprüfung
komplexer Herstellergeräte, Normausgaben-/Lizenzprüfung und Kays elektrotechnische
Abnahme bleiben offen. M6-Geräteabnahme und produktives Mehrhost-HA werden durch
M7 nicht als erledigt erklärt.

## Bedienung

Projekt → Schaltplan öffnen. Die Bauteilbibliothek enthält jetzt:

- **Planart / Maßstab:** Installationsplan mit PNG-/JPEG-Grundriss (als PNG
  eingebettet), Bildherkunft, Revision und Sperre. Zwei Punkte und eine bekannte
  Strecke bestimmen den Maßstab. Perspektivprüfung muss ausdrücklich bestätigt
  sein; zwei Punkte entzerren kein Schrägfoto. Ausrichten/Ersetzen der Vorlage
  verwirft die Kalibrierung. Stromkreise enthalten Verteilung und Geräte;
  Leitungswege verbinden zwei platzierte Geräte über gewählte Zwischenpunkte.
  Länge inklusive Zuschlag folgt aktuellen Gerätepositionen und Kalibrierung.
- **Aufbauzeichnung:** Planart umschalten und mm je Zeichnungseinheit festlegen.
  Im Geräteinspektor „Artikel / Maße zuordnen“ wählen. Rechtecke verwenden die
  festgehaltenen Artikelmaße; fehlende Maße, Überschneidungen und Blattgrenzen
  erzeugen Prüffunde. Leitungsweglängen verwenden hier den Millimetermaßstab,
  auch nach einem Wechsel von einer zuvor kalibrierten Installationsansicht.
  Keine automatische Montageabstandsprüfung.
- **Automatisierung:** Generische SPS-, FU- und Sicherheitsgeräte mit benannten
  Anschlüssen, Kontaktbaum und bestehenden Querverweisen. SPS-Signale I0/I1/Q0/Q1
  sind strukturiert gespeichert. Diese synthetischen Blöcke bilden keine
  herstellerspezifische Gerätefunktion oder Sicherheitszertifizierung ab.
- **Makrobibliothek:** Persönliche, firmenweite und global freigegebene Vorlagen.
  Name/Gruppen, Herkunft, Lizenz und Historie bleiben sichtbar. Persönliche
  Makros sind auch vor anderen Firmenadmins geschützt; Firmenmakros pflegen
  Admins. „Projekt als Makro speichern“ erfasst sämtliche Projektblätter.
  Einfügen erzeugt neue Blätter, Geräte, BMK, Kontakte, Kabel, Fortsetzungen,
  Stromkreise, Wege und Rechenfall-IDs. Eingefügte Daten sind unabhängige Kopien.
  Es gibt noch keine Auswahl eines beliebigen Ausschnitts innerhalb eines Blatts.
- **Berechnungen:** Leitungs-/Spannungsfall und stationäre Wärmebilanz als
  ungeprüfte Rechenvorschläge. Eingaben, Einheiten, Quellen, Einsatzbedingungen,
  Zwischenergebnisse und Grenzen bleiben sichtbar und werden im PDF ausgegeben.
- **Material / ERP:** Aktuellen Entwurf als Importvorschau herunterladen.
  Physische Geräte zählen einmal, auch wenn sie mehrfach dargestellt sind.
  Fehlende Artikelzuordnungen bleiben als offene Positionen sichtbar.

Planung, Makroeinfügen und Rechenfälle werden zunächst übernommen und danach
mit „Speichern“ als gemeinsame Projektversion gesichert. Rückgängig und
Versionskonflikte funktionieren wie im Schaltplan. Unter 1000 px Breite oder
500 px nutzbarer Editorhöhe bleibt die Bearbeitung gesperrt. Vorbereitete native
Offline-Projekte enthalten auch Grundrisse und Rechenfälle; der Makrokatalog
selbst benötigt eine Verbindung. Eingefügte Makrokopien sind offline vorhanden.

## Berechnungsumfang

Spannungsfall: `ΔU = f · I · L_km · (R · cosφ + X · sinφ)`, mit `f = 2`
für einphasig bzw. `sqrt(3)` für symmetrisch dreiphasig. R und X werden in Ω/km
für den gewählten Querschnitt und die angegebene Betriebstemperatur eingegeben.
Aus `R·S = konstant` wird zusätzlich ein rein rechnerischer Mindestquerschnitt
für die eingegebene Spannungsfallgrenze abgeleitet. Annahmen: unverändertes
Leitermaterial, Temperatur und X. Erreicht der Reaktanzanteil bereits die Grenze,
gibt es unter diesen Annahmen keinen endlichen Mindestquerschnitt.

Die eingegebene Relation `Ib <= In <= Iz` prüft ausschließlich die benannten
Stromwerte. Keine hinterlegten DIN-VDE-Tabellen, keine automatische Auswahl eines
Normquerschnitts, keine Prüfung von Kurzschluss, Abschaltbedingungen, Verlegeart,
Häufung, Neutralleiterbelastung oder Schutzkoordination. Ein Querschnittwechsel
benötigt neue Hersteller-/Strombelastbarkeitsdaten. Rechengrundlage:
[Schneider Electric, Electrical Installation Guide](https://www.electrical-installation.org/enwiki/Calculation_of_voltage_drop_in_steady_load_conditions).

Wärme: Summe der gewählten physischen Geräteverluste minus
`k · A_wirksam · (T_innen − T_umgebung)` ergibt den Kühlbedarf; ein negativer
Wert wird als Heizbedarf ausgewiesen. Geräteverluste benötigen Bezugsbedingungen.
Fläche und Wärmeübergang werden ausdrücklich eingegeben. Einbau, Lüftung,
Hotspots, Solarstrahlung und dynamische Lasten sind nicht automatisch modelliert.
Rechengrundlage: [Rittal, Technical aspects of enclosures](https://info.rittalenclosures.com/hubfs/PDFs_-_White_Papers/Brochure-Technical-Aspects-of-Enclosures.pdf).

Fehlende oder unplausible Daten ergeben **kein Ergebnis**. Ergebnisse werden aus
dem aktuellen Modell neu berechnet, nicht als möglicherweise veraltete Zahlen
im Projekt gespeichert. Rechenfälle erzeugen Prüffunde für die fachliche Abnahme.

## Daten und Schnittstellen

Optionale Zeichnungsfelder: `plans`, `calculations`, `macroSources`;
Geräte tragen Artikel-Snapshots und optionale SPS-Kanäle. Bibliothek V3 unterstützt
bestehende V1/V2-Projekte. Bilder bleiben Rasterdaten ohne native CAD-Objekte.
Maximal 2400 × 2400 Pixel und 2,8 Mio. Base64-Zeichen je gespeicherter PNG-Datei;
die Oberfläche normalisiert auf maximal 1600 Pixel Kantenlänge. Zeichnungs-,
Makro-, Automations- und Beitragsanfragen sind auf 4 MiB begrenzt; mehrere große
Bilder können diese Gesamtgrenze erreichen. Nginx lässt bis zu 5 MiB durch.

`/api/v1/macros/`: GET/POST; `/<id>` GET/PATCH mit Versionsvergleich;
`/<id>/history` GET; `/<id>/copy` POST mit Quellversion/Zielbereich;
`/global/<id>/copy` POST prüft den veröffentlichten Katalogstand serverseitig.
PostgreSQL-Migration 7 ergänzt den Dokumenttyp `macro`. Öffentliche Makros laufen
als eigener Beitragstyp durch denselben Rechte-/Moderationsprozess wie Artikel.
Sie erscheinen nicht in der Artikelsuche. Veröffentlichung überträgt bewusst
alle enthaltenen Daten einschließlich Grundrissen; die Vorschau und Rechte
müssen vorher bestätigt werden. Rückzug entfernt öffentliche Sichtbarkeit,
ändert aber keine bereits kopierten Projektstände.

`libre-ecad.material.v1` enthält Backend-/Projekt-ID, Projektversion,
Zeichnungs-SHA256, Paket-ID, Artikel-ID/-version, Variante, Stückeinheit, Mengen
und Gerätekennungen. SHA256 ist eine Integritätsprüfung, keine Absendersignatur.
Der WerkkernERP-Zweig `feat/libre-ecad-material-preview` liest dieses Format,
prüft Dubletten und lässt vorhandene ERP-Artikel ausdrücklich zuordnen. Er
exportiert einen Zuordnungsentwurf. Wiederholtes Laden ersetzt die Vorschau.
Es gibt keine Artikelanlage oder automatische Angebots-, Auftrags- oder
Lagerbuchung. Der getrennte ERP-Zweig ist nicht in die laufende ERP-Instanz
übernommen; parallele dortige Entwicklungsänderungen bleiben unberührt.

## Ausgeführte Prüfungen

- Core: 24 Tests, einschließlich dynamischer Weglänge, fehlender Eingaben,
  Querschnitt-Rückrechnung, Wärme, Bildvalidierung und zweifacher Makrokopie
  mit unabhängigen Netzen, SPS-Kanälen, eigenen Symbolen und Planreferenzen.
- Firmendienst: 29 Tests; globaler Katalog: 14 Tests. Rollen, persönliche
  Sichtbarkeit, Firmenisolation, Versionskonflikte und Moderation.
- Flutter: 15 Tests inklusive verschlüsseltem Offline-Rundlauf und lokalem
  PDF mit PNG-Grundriss/Rechenfällen. Statische Analyse ohne Fehler.
- `scripts/smoke-m7.py`: echte HTTP-/PostgreSQL-Persistenz, PDF-Bildprüfung,
  Firmenabgrenzung, Makrohistorie, globale Freigabe/Kopie/Rückzug.
- `scripts/browser-m7.py`: tatsächlicher Bild-Upload, Zweipunkt-Kalibrierung,
  Aufbauansicht, Rechenwerte, Materialdownload, Makroeinfügen und kompakter
  Lesemodus in Chromium.
- Web-, Linux- und Android-Release-Build erfolgreich.
- WerkkernERP: Analyse `lib test` ohne Befunde; 321 Tests einschließlich einer
  vom LibreECAD-Generator erzeugten Materialdatei und sichtbarem Zurücksetzen
  beim erneuten Laden. Web-Release auch nach Abgleich mit dem aktuellen
  ERP-Hauptzweig gebaut.

Synthetischer Beispieldatensatz: `dart run bin/planning_sample.dart` im Core-Paket.
Die Skripte nutzen ausschließlich isolierte TEST-Firmen. Zugangsdaten bleiben in
lokalen, nicht versionierten Dateien mit Modus 0600.
