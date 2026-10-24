# M4 – Zeichenkern und Speichervertrag

## M4.1 Objektmodell

`backend/ecad_core` enthält das gemeinsame Dart-Modell für Client und Server.
Schema 1 trennt Blätter, Betriebsmittel, Symbolinstanzen, Geräteanschlüsse,
explizite Knoten, paarige Blattfortsetzungen, Leitungen und Kabel/Adern.
IDs sind unabhängig von BMK und Position. Mehrfachdarstellungen referenzieren
jeweils ein Gerät; Anschlüsse tragen dieselbe elektrische Identität über alle
Ansichten. Spule und Kontakt desselben Relais haben unterschiedliche Anschlüsse.
Keine automatische elektrische Durchleitung durch ein Gerät oder Schaltsimulation.

Netze sind aus expliziten Endpunktbeziehungen abgeleitete Zusammenhangskomponenten;
ihr Schlüssel ist der kleinste stabile Endpunktschlüssel der Komponente. Bei
Trennung/Vereinigung kann sich dieser abgeleitete Schlüssel ändern. Geometrie,
Kreuzungen, gleiche Texte und Nähe erzeugen niemals eine Verbindung. Eine
Blattfortsetzung besteht aus genau zwei Enden auf unterschiedlichen Blättern
mit gemeinsamer `linkId`. Ein Kabel besitzt eindeutig benannte Adern; eine Ader
kann höchstens einer Leitung zugeordnet sein. Klemmen sind Geräte mit einem
Verbindungspunkt, an dem explizit mehrere Leitungen zusammentreffen können.

Die kleine Bibliothek besteht ausschließlich aus eigenen synthetischen
Demonstrationsglyphen unter der Repository-MIT-Lizenz. Keine normierte Symbolbibliothek,
keine Herstellerverifikation und keine Berechnungs-/Anlagenfreigabe.
BMK-Vorschläge folgen `Blatt-BeispielkennungSpalte`, erstes Gerät ohne Suffix,
dann `.1`, `.2`. Verschieben/Blattänderung erhält das BMK; die Oberfläche bietet
bewusste Neubenennung an. Querverweise werden immer aus Geräte-ID und aktueller
Blatt-/Rasterposition abgeleitet. Doppelte BMK werden abgewiesen.

## Speicherung und API

**PostgreSQL ist die einzige schreibbare Wahrheit für M4-Arbeitsstände.**
Die Zeichnung gehört zum bestehenden Projektdokument, nicht zu einem zweiten
unabhängigen Datensatz. Zeichnung, Metadaten und Mitgliedschaft teilen eine
CAS-Version. Eine erfolgreiche Änderung schreibt aktuellen Stand und Historie
in einer SQL-Anweisung atomar. Eine parallele Metadaten-/Mitgliedschaftsänderung
lässt einen veralteten Zeichnungsschreibversuch scheitern (409 bzw. 404 nach Entzug).
Bestehende M1–M3-Projekte ohne Zeichnung bleiben lesbar; kein Datenbankumbau nötig.

Alle Pfade unter `/api/v1/projects/{id}/drawing`, mit Firmen-Sitzung:

- `GET`: Projektversion, Zeichnung (anfangs `null`), abgeleitete Netze.
- `PUT`: `{version, drawing}`; nur Firmenadmin oder zugewiesener aktiver Zeichner.
  Strikte Schemaprüfung, vollständiger atomarer Arbeitsstand, maximal 128 KiB.
- `GET /history`: gespeicherte Projektversionen mit Zeichnung und Akteur/Zeit.
- `GET /export`: deterministisches UTF-8-JSON und SHA-256 eines atomar gelesenen
  Projektstands ohne Benutzer-/Mitgliedschaftsdaten. Zustand ausdrücklich
  `unapproved-working-copy`. Kein fachliches Festschreiben.

Wiederherstellung eines älteren Inhalts benutzt dieselbe `PUT`-Versionsprüfung
und erzeugt einen neuen Historieneintrag. Bestehende Historie wird nie ersetzt.
Bei Konflikten bleibt der lokale Entwurf erhalten; weder Auto-Merge noch Retry
mit einer heimlich erhöhten Versionsnummer.

**Git-Grenze:** Git kann deterministische Exporte als abgeleitete Sicherung halten;
Git wird in M4 nicht parallel zur SQL-Transaktion beschrieben. Ein Git-Ausfall
kann daher keinen halben Datenbankstand erzeugen. In M5 werden fachlich
festgeschriebene, unveränderliche Pakete mit Git-Commit und Bibliotheksständen
gebunden. Bis dahin sind weder SQL-Version noch Git-Commit eine Fachfreigabe.

## M4.2 Bedienung

Firmen-App → Projekte → Projekt öffnen → **Schaltplan öffnen**.

- Links aufklappbare synthetische Bibliothek mit Suche. Symbol wählen und auf
  dem Blatt platzieren; Ziehen verschiebt auf das 20er-Raster. „Ansicht bewegen“
  schwenkt, die Schaltflächen unten rechts zoomen/passen das Blatt ein.
- „Verbinden“ und zwei Anschlüsse wählen. Werkzeugwechsel bricht den ersten
  Endpunkt ab. Verbindungen lassen sich rechts trennen, einer Kabelader zuordnen
  oder ausdrücklich an einem neu angelegten Knoten aufteilen. Ein Knoten über
  einer bestehenden Linie verbindet sie nicht automatisch.
- Gerät wählen → Kennung/Anschlüsse bearbeiten. „Weitere Darstellung“ wählt
  eine weitere Ansicht **desselben Geräts**, danach Blatt wählen und platzieren.
  Querverweis-Schaltflächen springen zur jeweiligen Ansicht. Positionsänderungen
  ändern Querverweise sofort, BMK nur nach bewusster Auswahl des Vorschlags.
- Blätter anlegen/umbenennen/umnummerieren; paarige Fortsetzungen anlegen und
  ihre Positionen/Beschriftung rechts bearbeiten. Fortsetzung verbinden wie einen
  Anschluss. Kabel/BMK/Ader/Farbe sind strukturierte Daten; keine Farbnormprüfung.
- Zwei gleichberechtigte Arbeitsproben: Verteilerabgang und Steuer-/Motorabgang,
  jeweils zwei Blätter, Relaismehrfachansicht, Fortsetzung und Kabelader.
- Rückgängig/Wiederholen (60 Bearbeitungsschritte), explizites Speichern,
  Historie mit Wiederherstellung als Entwurf. Ein Versionskonflikt zeigt beide
  vollständigen Zeichnungen; Nutzer kann abbrechen, die Serverzeichnung laden
  oder bewusst die lokale Zeichnung speichern. Erneute Konkurrenz bleibt 409.
- Backendzugriff wird beim Laden, Speichern und alle 15 Sekunden geprüft.
  Erkannter Ausfall/Entzug sperrt Bearbeitungswerkzeuge und erhält den Entwurf
  im Fenster. Keine zugesagte Offline-Funktion; Browserneuladen verwirft Entwürfe.
  Kleine Zeichenfenster (unter 1000 px Breite oder 500 px verfügbarer Höhe)
  zeigen einen Lesemodus. PDF und Fachfreigaben sind erst M5.
