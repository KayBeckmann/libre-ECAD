# M3 – Katalogbeiträge und Betreiberverwaltung

Stand: 24.10.2026. Technisch für die LAN-Vorschau implementiert. Die fachliche
Freigabe für öffentlichen Upload- und Mietbetrieb bleibt ein eigenes Entscheidungstor.
Es gibt weiterhin keinen CAD-/Symboleditor und keine Berechnungsfreigaben.

## Einstieg

- Firmenfrontend: `http://<LAN-Host>:8185`; „Meine Katalogbeiträge“ im Startbildschirm.
- Getrennte Betreiberoberfläche: `http://<LAN-Host>:8186`, Superadmin-Anmeldung.
- Neue Zugänge: Token aus der Betreiberoberfläche sicher weitergeben; im Firmenfrontend
  „Zugang aktivieren“ wählen und ein eigenes Passwort setzen. Token gelten sieben Tage,
  sind einmalig und werden nur gehasht gespeichert. Keine Tokens in URL-Parametern.
- Betreiber- und Firmenfrontend halten Sitzungstokens ausschließlich im Arbeitsspeicher.
  Die Betreiberoberfläche nutzt lokale HTML/CSS/JS-Dateien mit einer Content Security Policy.
- Alle drei Dienste nutzen Verbindungspools (maximal acht Verbindungen pro Dienst).
  PostgreSQL-Transaktionen reservieren ihre Verbindung. nginx löst Docker-DNS regelmäßig
  neu auf, damit ein ersetzter Backendcontainer keinen dauerhaften 502-Fehler verursacht.

## Publikation und Herkunft

1. Nutzer erstellen eine **eigene öffentliche Vorschau**. Aus der lokalen Bibliothek lassen
   sich Artikelnummer und Bezeichnung bewusst auswählen. Öffentliche Herkunft, Namensnennung
   und Datenlizenz werden gesondert eingegeben; optionale technische Zahlen ebenfalls.
2. Die API übernimmt ausschließlich diese freigegebenen Felder. Keine privaten Notizen,
   Projekte, lokalen Symbol-/Ansichtsreferenzen, internen Herkunftsketten oder Kontaktangaben
   werden automatisch kopiert. Technische Unbekannte bleiben `null`; null Watt bleibt `0`.
3. Unterstützte Lizenzkennungen für diesen Workflow: `CC0-1.0`, `CC-BY-4.0`, `CC-BY-SA-4.0`.
   Die Rechtebestätigung ist eine dokumentierte Erklärung des Einreichers, kein Nachweis,
   dass beliebige fremde Herstellerdaten neu lizenziert werden dürften.
4. Entwurf → Einreichung → Superadmin-Prüfung → Veröffentlichung. Nur der Beitragseigentümer
   kann seinen Entwurf bearbeiten/einreichen; der Superadmin kann prüfen, zurückgeben,
   freigeben und zurückziehen. Eine Rückgabe erhält die Begründung in der Beitragshistorie.
5. Eine Freigabe erzeugt einen **eigenen öffentlichen Versionsstand**. Während einer neuen
   Bearbeitung/Prüfung bleibt die letzte Freigabe sichtbar. Interne Revision und öffentliche
   Artikelversion sind deshalb unterschiedliche Zähler. Versionskonflikte liefern HTTP 409.
6. Ein Rückzug entfernt den aktuellen Treffer, erhält aber veröffentlichte Versionen und
   den öffentlichen Rückzugsgrund in der Herkunftshistorie. Bereits angelegte lokale Kopien
   bleiben unabhängig und behalten Lizenz, Namensnennung, Quelle und Quellversion.
7. Dublettenhinweise vergleichen Artikelnummern ohne Beachtung der Großschreibung mit dem
   veröffentlichten Bestand. Es gibt keine automatische Zusammenführung oder Variantenprüfung.

Der private Workflow benötigt opake Firmen-/Nutzer-IDs zur Zugriffskontrolle. Er enthält
keine Benutzerkonten, Passwörter oder Projekte. Öffentliche APIs liefern nur bereinigte
Freigabesnapshots und öffentliche Ereignisse, niemals interne IDs, Prüfnachweise oder
Entwurfsstände. Ein technischer Wert bleibt immer `unverified`.

## Herstelleridentität

- Ausschließlich der Superadmin ordnet einer lokalen Firma eine Herstelleridentität zu.
  Die Zuordnung erfordert Bestätigung, Grund und eine Referenz auf den Nachweis für
  Identität und Vertretungsberechtigung. Vorgesehener manueller Ablauf: unabhängigen
  Herstellerkontakt prüfen, Berechtigung bestätigen lassen, Nachweisreferenz dokumentieren.
- Aktive Firmenadmins dieser zugeordneten Firma bilden den Herstellerzugang. Sie reichen
  ausschließlich in den zugeordneten Herstellerbereich ein. Normale Nutzer/Zeichner bleiben
  User-Upload-Autoren. Der Browser darf den Herstellerbereich nicht frei bestimmen.
- Ein einmal zugeordneter Herstellername und die Herkunftskategorie eines Beitrags bleiben
  unverändert. Ein früherer User-Upload wird nicht nachträglich zum Herstellerbeitrag.
- Entzug sperrt neue Hersteller-Einreichungen und Freigaben. Die Herkunft bereits
  veröffentlichter Versionen bleibt bestehen. Falsche Artikel können zusätzlich bewusst
  zurückgezogen werden. `identity-only` bedeutet Identitätsprüfung zum Freigabezeitpunkt,
  ausdrücklich keine technische Prüfung der Artikeldaten.
- Synthetische Abnahmezuordnungen heißen **TEST** und stellen keine realen Identitätsprüfungen dar.

## Firmen, Verträge und Zahlungsvorgänge

Managed-Firmen werden zusammen mit dem ersten Admin in **einer Transaktion** angelegt.
Eine wiederholte Vorgangsnummer legt keine zweite Firma an; ein verlorener Aktivierungstoken
wird über „Aktivierung neu“ ersetzt. Ein belegter Benutzername lässt die gesamte Anlage
zurückrollen. Die früheren zweistufigen Superadmin-Provisionierungsrouten liefern im
laufenden M3-Stack HTTP 410; neue Clients verwenden `/operator`.

Externe Backends sind ausschließlich Verzeichniseinträge mit URL und verantwortlichem
Betreiber. Diese URLs werden nicht serverseitig abgerufen. Kays Konsole provisioniert dort
keine Nutzer, verrechnet keine Managed-Zahlungen und setzt keine Remote-Sperre. Ein Wechsel
zwischen externem und Managed-Betrieb ist keine Metadatenumschaltung; Daten-/Kontenmigration
und föderierte Herstelleridentität sind noch nicht implementiert.

**Abrechnungsquelle in der LAN-Vorschau: manuell.** Ohne erfassten Vertrag ist der Stand
„ungeklärt“; es werden keine Zahlungen aus einem Vertragsstatus abgeleitet.

- Vertragszustände: ungeklärt, Testphase, aktiv, beendet; jeweils mit Dokumentreferenz.
- Zahlungsjournal: offen, erfolgreich, fehlgeschlagen; zwingend Betrag, Währung,
  Belegdatum, Belegreferenz und Begründung. Die Oberfläche verwendet EUR mit Centbeträgen.
- Korrekturen sind neue Einträge mit Referenz auf den letzten Beleg. Originale werden
  nicht überschrieben; doppelte Korrekturen desselben Standes werden zurückgewiesen.
- Keine Abbuchung, Rechnungserstellung, Provider-Webhooks oder automatische Sperre.
  TEST-Belege der Abnahme dokumentieren **keine realen Geldbewegungen**.

## Sperren, Zugänge und Audit

Eine Managed-Sperre bewahrt die Daten, verhindert neue Anmeldungen und macht vorhandene
Sitzungen ungültig. Auch eine Entsperrung reaktiviert keine alten Sitzungstokens. Die Prüfung
gilt bei jeder neuen Anfrage; bereits laufende Anfragen und bereits geladene Daten können
nicht rückwirkend vom Endgerät entfernt werden. Offline-Arbeit/-Synchronisation folgt M6.

Die Konsole fordert Grund und bewusste Bestätigung. Der Betreiber informiert die Firma
über den vereinbarten Kontaktweg; es gibt noch keinen Mail-/Benachrichtigungsdienst.
Wiederfreigabe ist eine eigene auditierte Aktion, anschließend melden Nutzer sich neu an.
Auch deaktivierte/reactivierte Nutzer erhalten keine alten Sitzungen zurück. Der letzte
aktive, aktivierte Admin bleibt selbst bei parallelen Deaktivierungen geschützt.

„Aktivierung neu“ verwirft vorherige Einladungen und Sitzungen. Das bisherige Passwort bleibt
bis zur Einlösung gültig, damit ein Recovery-Vorgang nicht den letzten Admin aussperrt.
Die Einlösung ersetzt das Passwort und verwirft erneut alle Sitzungen dieses Nutzers.

Akteur, Zeitpunkt, Grund und Zustand werden atomar mit der jeweiligen Änderung gespeichert.
Katalog-, Zuordnungs- und Vertragsrevisionen liegen in `m3_records`/`m3_history`,
Zugriffsänderungen in `management_audit`. Es gibt keine API zum Umschreiben dieser Historien;
die Datenbankadministration bleibt eine eigene Vertrauensgrenze. Kein verteilter
Transaktionsanspruch zwischen den drei Diensten: Jeder Vorgang hat genau einen zuständigen
Dienst, dessen Zustand und Audit gemeinsam committen.

## Schnittstellen

Alle neuen Schreib-/Prüfaktionen nutzen JSON-POST, begrenzt auf 128 KiB. Je nach Aktion
sind `version`, `confirmed: true` und `reason` Pflicht. Zeitüberschreitungen führen nicht
zu automatischer Wiederholung einer Änderung; erst den Serverstand neu laden.

| Adresse | Zugang | Aktionen |
| --- | --- | --- |
| Firmenservice `/api/v1/contributions` | Aktive Firmen-Session | `list`, `create`, `edit`, `submit`, `withdraw`, `history` |
| Superadmin `/operator` | Superadmin-Session | `overview`, `managed`, `catalog`, `external`, `contract`, `payment`, `history` |
| `managed.operation` | Superadmin | `list`, `create`, `users`, `audit`, `access`, `addAdmin`, `userAccess`, `activation` |
| `catalog.operation` | Superadmin | `list`, `inspect`, `history`, `manufacturerHistory`, `manufacturer`, `approve`, `reject`, `withdraw` |
| Global `/articles`, `/articles/<id>` | Öffentlich lesbar | Nur Beispiele und aktuelle Freigaben |
| Global `/articles/<id>/history` | Öffentlich lesbar | Freigabesnapshots und Rückzugsgründe |

Firmen- und Superadmin-Service setzen Akteur und Betriebsmodus selbst; Browserangaben
werden überschrieben. Interne Firmen-/Katalogrouten benötigen das gemeinsame Dienstsecret
und sind an beiden Web-Proxys gesperrt. Die LAN-Direktports 8181–8183 bleiben wie zuvor
für die Entwicklungsumgebung offen, die drei Datenbankports bleiben intern.

## Abnahme und Wiederholung

```bash
# Im Repository /home/kay/git/libre-ECAD
./scripts/build-web.sh
docker compose up -d --build
python scripts/smoke-m3.py
python scripts/stress-m3.py
python scripts/concurrency-m3.py
python scripts/browser-m3.py     # Python Playwright + Chromium erforderlich
python scripts/smoke-m2.py       # Regression der lokalen Bibliotheken/Projekte
```

Die Live-Skripte erzeugen eindeutig synthetische Firmen, Konten, Artikel und Belege.
`smoke-m3.py` legt für die Browserprüfung einen temporären Zustand mit Testcredentials
unter `/tmp/libre-ecad-m3-state.json` (0600) an. Nach Abschluss Testsitzungen widerrufen und
diese Datei entfernen. Die Skripte nacheinander ausführen: Sperrtests widerrufen absichtlich die Sitzungen ihrer Testfirmen. Reguläre Zugangsdaten gehören ausschließlich in lokale, ignorierte
Dateien; weder in Commits noch Vault-Dokumente.

Ergebnisse und verbleibende Freigabepunkte werden in Roadmap und Brainstorming im Vault
nachgeführt. Für öffentlichen Betrieb müssen Kay und die zuständigen Verantwortlichen
Lizenz-/Moderationsverfahren, zulässige Identitätsbelege, Vertrags-/Abrechnungsquelle,
Benachrichtigung und Aufbewahrung fachlich abnehmen. TLS, Login-Rate-Limits und eine
rein interne Dienst-API sind weiterhin Voraussetzungen für Internet-Exposition.

### Technische Abnahme am 24.10.2026

- 50 Backendtests (Shared 5, Superadmin 12, Katalog 13, Firma 20), sechs Fluttertests;
  statische Analyse aller Dart-Pakete und Flutter ohne Befunde.
- Live-API-Abnahme mit zwei synthetischen Firmen einschließlich Rollen-/Mandantengrenzen,
  atomarer Provisionierung/Fehlerrücknahme, Zahlungsjournal, Sperren, Recovery,
  Herstellerzuordnung/-entzug, Publikation, Überarbeitung, Rückzug und lokaler Kopie.
- Browserabnahme über die LAN-Adressen: Firmenwechsel, Audit, Sperre/Entsperrung,
  Zuordnung/Entzug, Tokenaktivierung, Flutter-Beitragsvorschau und Moderationsfreigabe;
  mobile Betreiberansicht ohne horizontalen Überlauf, keine JS-Fehler oder externen Abrufe.
- 120 überlappende Anfragen über alle Dienste ohne Verbindungsfehler; parallele
  Admin-Deaktivierungen erhalten mindestens einen aktiven, aktivierten Admin.
- M2-Live-Regression weiterhin erfolgreich: Projekte/Mitgliedschaften, persönliche und
  Firmenbibliothek, Versionskonflikte, Herkunftskopien und Katalogimport.
- Backup/Restore aller drei Datenbanken in temporäre Datenbanken: 15 Anwendungstabellen
  mit identischen Zeilenzahlen und Inhaltsprüfsummen. Privater Testmarker fehlt in allen
  globalen Workflowrevisionen. Neustartvergleich erfolgt bei pausierten Schreibzugriffen,
  damit neue Testvorgänge den Inhaltsvergleich nicht verfälschen; alle 15 Tabellen blieben
  nach dem Datenbankneustart inhaltlich identisch.
