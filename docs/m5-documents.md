# M5 – Dokumentation und festgeschriebene Projektstände

Stand: 24.10.2026. Aus dem Projekt führt **Schaltplan öffnen → Dokumente und Freigabe** zur Ausgabe. Die Auswahl benennt eine gespeicherte Arbeitsversion oder einen festgeschriebenen Stand. Ungespeicherte Editoränderungen werden ausdrücklich nicht als gespeicherte Ausgabe dargestellt.

## Dokumente

Der gemeinsame Dart-Kern leitet Klemmen, Verbindungen, Kabeladern und Material aus genau einem Projektobjekt ab. Eine Relaisspule und ihr Kontakt zählen als ein Gerät. Deckblattdaten werden unter **Deckblatt und Projektmetadaten** erfasst: Kunde, Anlage, Auftrag, Baujahr, Standort, Verantwortlich und Dokumentnummer. Listen sind Geräte-/Verbindungslisten der vorhandenen synthetischen Bibliothek; eine Herstellerstückliste mit Artikelzuordnung wird dadurch nicht vorgetäuscht.

Die A3-PDF enthält Deckblatt, ein aus den tatsächlichen Seiten berechnetes Inhaltsverzeichnis, Zeichnungsblätter, Projektbeschreibung, Plausibilitätsprüfung und Listen. Festgeschriebene Ausgaben enthalten zusätzlich Freigabe und begründete Ausnahmen. Lange Tabellen und Texte werden umgebrochen, ohne Inhalte abzuschneiden. Jede Seite nennt Projektversion und Status. Schriftdateien sind lokal gebündelt; die Webausgabe lädt weder einen externen PDF-Viewer noch externe Schriftressourcen für die unterstützten Zeichen nach.

## Prüfungen und bewusste Freigabe

Strukturfehler (unter anderem ungültige Verweise und doppelte BMK) verhindern bereits das Speichern; sie sind nicht über Ausnahmen aufhebbar. Der Prüfkern liefert dafür, soweit zuordenbar, die betroffene Objekt-ID. Offene dargestellte Anschlüsse, mehrfache Belegung eines Nicht-Klemmen-Anschlusses und unvollständig angeschlossene Knoten/Fortsetzungen sind Hinweise. Das sind ausdrücklich Regeln der synthetischen Bibliothek, keine Bewertung elektrischer Sicherheit oder Normkonformität. Ob eine Verbindung beabsichtigt ist, muss die bearbeitende Person entscheiden.

Firmenadmins können einen sichtbaren aktuellen Stand fachlich festschreiben. Dazu müssen sie jeden Hinweis begründen, eine Freigabebegründung eingeben und die Prüfung ausdrücklich bestätigen. Zeichner dürfen Dokumente ihrer zugewiesenen Projekte lesen und herunterladen. Jede Freigabe prüft serverseitig Rolle, Firmen-/Projektzugriff, sämtliche Hinweise und die aktuelle Projektversion erneut. Gründe gelten ausschließlich für die geprüfte Version. Eine zwischenzeitliche Änderung liefert HTTP 409; es gibt keinen stillen Merge und keine automatische Freigabe nach Konfliktauflösung.

Hinweise zu einem geladenen Arbeitsstand führen zum betroffenen Blatt/Objekt im Editor. Bei einer anderen historischen Version muss diese zunächst bewusst über die Historie geladen werden. Konflikte zeigen abweichende Objekte sowie beide vollständigen Zeichnungen. Die aktive Entscheidung zum Speichern ersetzt keine erneute Prüfung/Freigabe.

## Speicherung und Ausfallgrenzen

SQL bleibt die maßgebliche Quelle für Arbeitsstände und den fachlichen Freigabestatus. Die vorhandene atomare Compare-and-swap-Operation schreibt Projekt und unveränderliche Historie in einem SQL-Statement. Eine Freigabe erzeugt eine neue Projektversion; ihr Paket dokumentiert die davor ausdrücklich geprüfte Quellversion. Nachfolgende Arbeitsänderungen übertragen das Paket nicht in jeden neuen Stand. Frühere Pakete bleiben über die Historie erreichbar.

Pro Firma/Projekt liegt ein echtes bares Git-Repository unter `PROJECT_ARCHIVE_DIR/<sha256(company/project)>.git`. Das Compose-Volume `project-archives` hält es persistent. Ein Commit enthält:

- `project.json`: Zeichnung und Metadaten der Quellversion, ohne Projektmitglieder oder Sitzungstoken.
- `documents.json`: die daraus abgeleiteten Listen.
- `library.json`: fixierte synthetische Bibliotheksdefinitionen; Bildliste ist leer, weil Projektbilder erst später hinzukommen.
- `sheet-<nummer>.svg`: konkrete Blattgeometrie dieses Standes.
- `checks.json`: Prüfergebnisse und Regelversion zum Freigabezeitpunkt.
- `approval.json`: bestätigender Nutzer, Zeitpunkt, Grund und Ausnahmen.
- `output.pdf`: unveränderliche Originalbytes der Ausgabe.
- `manifest.json`: SHA-256-Prüfsummen aller enthaltenen Nutzdateien.

Git wird vor dem SQL-Compare-and-swap geschrieben. Nur der erfolgreiche SQL-Historieneintrag veröffentlicht eine Freigabe. Ein Git-Fehler veröffentlicht nichts; ein konkurrierender Schreibzugriff kann einen unveröffentlichten Git-Kandidaten hinterlassen. Die `candidate-*`-Refs sind daher ausdrücklich **keine Freigabeliste**. Veröffentlichte Commits verweisen auf den vorherigen veröffentlichten Commit als Elternstand. Es gibt keine automatische Zusammenführung.

Die vollständigen Paketdateien, Commit-Metadaten und Eltern-IDs stehen auch in der SQL-Historie. Nach Wiederherstellung nur der Datenbank baut der Dienst die fehlende Git-Kette beim Abruf wieder auf und prüft identische Commit-IDs. PDF-Dateien alter Freigaben werden aus gespeicherten Bytes ausgeliefert, nicht mit einer eventuell neueren Bibliothek nachgerendert. Bei nicht verfügbarem Archiv bleibt der Abruf mit einer klaren Fehlermeldung gesperrt; er wechselt nicht unbemerkt zu einer anderen Quelle.

Betrieb: Datenbank und Archiv-Volume sichern. `scripts/smoke-m5.py` prüft zusätzlich den SQL-only-Wiederaufbau in einem synthetischen Testprojekt. Außerhalb von Compose sollte `PROJECT_ARCHIVE_DIR` auf ein dauerhaftes Verzeichnis und `PDF_FONT_DIR` auf `company_users_service/assets/fonts` zeigen. Ohne gesetztes Archivverzeichnis verwendet der lokale Entwicklungsstart ein temporäres Verzeichnis. Eine installierte native Anwendung nutzt den Betriebssystem-Dialog von `printing`; vollständige native/offline Abnahme gehört zu M6.

## HTTP-Vertrag

Alle Endpunkte liegen unter `/api/v1/projects/<id>` und benötigen die Firmenanmeldung:

| Methode/Pfad | Verhalten |
| --- | --- |
| `GET /documents?version=N` | Explizite gespeicherte Arbeitsversion; Projekt, Listen, Hinweise und PDF als Base64 |
| `GET /documents?release=ID` | Unveränderliches Paket einer sichtbaren Freigabe; Commit und PDF-Prüfsumme |
| `GET /releases` | Metadaten der veröffentlichten Freigaben, aufsteigend |
| `POST /releases` | `{version, reason, exceptions: {findingId: reason}, confirmed: true}`; Admin, Version und alle Gründe erforderlich |

Projektanlage/-änderung akzeptiert zusätzlich `metadata` mit den oben genannten Feldnamen. Eine Ausgabe ohne Quellauswahl wird mit HTTP 400 abgelehnt. Zugriffsgrenzen gelten auch für historische PDFs.

## Abnahme

- Dart-Prüfungen für Listen, geteilte Geräte, offene/überbelegte Anschlüsse, Strukturfehler und Objektzuordnung.
- PDF-Erzeugung und visuelle/Textprüfung; 50 Blätter sowie 100 Beschreibungszeilen einschließlich Endmarkierung bleiben erhalten, Inhaltsverzeichnis und Seitenzähler passen.
- `scripts/smoke-m5.py`: reale PostgreSQL-Dienste, zwei Firmen, Zeichnerrechte, Zugriffsentzug, fehlende Gründe, veraltete Versionen, Git-Ausfall, parallele Freigaben, Datei-/Commit-/Prüfsummenvergleich, alte PDFs, Archiv-Wiederaufbau und isoliertes Datenbank-Backup/Restore.
- `scripts/browser-m5.py`: echte Anmeldung, Dokumentauswahl, Hinweissprung, Arbeits-PDF, begründete Freigabe, Download einer aktuellen und einer älteren Freigabe, kleines Fenster und gesperrte externe Ressourcen.
- M4-Browserabläufe bleiben als Regressionstest erhalten.

Die Integrationstests verwenden ausschließlich synthetische TEST-Projekte. Zugangsdaten liegen nur in geschützten temporären Dateien, nicht im Repository.
