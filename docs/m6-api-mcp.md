# M6.3 – fachliche API und MCP

Die vorhandene `/api/v1`-API bleibt versionsgebunden: [Projekte/Artikel](m2-api.md), [Zeichnung](m4-drawing.md), [Dokumente/Freigaben](m5-documents.md), [Offline](m6-offline.md). Bearbeitungen prüfen Firma, aktuellen Benutzerstatus, Projektmitgliedschaft und erwartete Projektversion serverseitig. Veraltete Stände ergeben 409. Freigaben bleiben ausdrücklich bestätigte Firmenadmin-Aktionen.

Im Projekt öffnet **API / MCP** eine eigene Zugangs- und Prüfoberfläche. Ein Benutzer bestätigt die Weitergabe genau dieses Projekts und wählt Lesen oder Lesen/Vorschläge. Der Zugang gilt acht Stunden, wird nur einmal im Klartext angezeigt, serverseitig ausschließlich als SHA-256-Hash gespeichert und lässt sich dort widerrufen. Jeder Aufruf prüft Ablauf, Widerruf, Aktivierung, Firma, Auth-Epochen und aktuelle Projektmitgliedschaft. Nach Entzug der Mitgliedschaft hilft der gespeicherte Scope nicht weiter. Ein API-Zugang ist keine normale UI-Sitzung.

## Endpunkte

Alle folgenden Pfade beginnen mit `/api/v1/automation`; Authentifizierung: `Authorization: Bearer ...`. Datenkörper sind JSON, maximal 4 MiB seit M7 (eingebettete Bildvorlagen). Leere/falsche Eingaben 400, nicht angemeldet/widerrufen 401, fehlende Aktionsberechtigung 403, nicht zugängliches Projekt 404, Versionskonflikt 409.

| Pfad / Methode | Zugang | Verhalten |
| --- | --- | --- |
| `GET /tokens` | UI-Sitzung | Eigene Zugänge samt Scope, Ablauf und Widerruf; kein Klartexttoken |
| `POST /tokens` | UI-Sitzung | `{confirmed:true,label,projectIds:[...],allowProposals:false}`; 1–50 bereits zugängliche Projekte; 201 mit einmaligem `token` |
| `POST /tokens/{hash}/revoke` | UI-Sitzung | Eigenen Zugang widerrufen; auditiert |
| `GET /projects` | API-Zugang | Nur aktuell zugängliche Projekte innerhalb des bestätigten Scopes (maximal 50) |
| `GET /projects/{id}` | API-Zugang | Aktueller Stand mit Metadaten und kanonischer Zeichnung; keine Mitglieder-/Sitzungsdaten |
| `GET /projects/{id}/documents?version=N` | API-Zugang | Abgeleitete Listen und Prüffunde genau des aktuellen Stands N; keine Freigabe |
| `POST /projects/{id}/proposals` | API-Zugang mit Vorschlagsrecht | `{version:N,reason,drawing}`; 201 mit Vorschlags-ID; verändert das Projekt nicht |
| `GET /review/{id}` | UI-Sitzung | Aktueller Projektstand, Vorschläge, abgeleiteter Status pending/stale/applied |
| `POST /review/{id}/{proposalId}/apply` | UI-Sitzung | `{confirmed:true,version:N}`; nur wenn Basis des Vorschlags und aktueller Projektstand N übereinstimmen |

Vorschläge sind unveränderliche, auditierte Records. Erst „Verglichen · Vorschlag übernehmen“ erstellt über atomaren Compare-and-Swap eine neue Projektversion. Beide Pläne sind blattweise nebeneinander sichtbar; exakte Objektdaten lassen sich zusätzlich vergleichen. Abbrechen lässt den Serverstand unverändert. Ein überholter Vorschlag muss auf neuer Basis neu erstellt werden; keine automatische Konfliktauflösung. Kleine Fenster erlauben keine Übernahme.

Die Projekthistorie ist maßgeblich für die Übernahme: Sie enthält Vorschlags-ID, Ersteller, Zugangshash, Begründung und bestätigenden Benutzer in derselben atomaren Projektänderung. Es gibt keine separate, möglicherweise widersprüchliche „applied“-Statusmutation. Tokens/Vorschläge liegen in `m3_records`/`m3_history` mit M6-Kinds und werden im normalen Firmen-DB-Backup mitgesichert. Diese Tabellen müssen bei Restore-/Integritätsprüfungen berücksichtigt werden.

## MCP lokal starten

Im Verzeichnis `mcp`: `npm ci --ignore-scripts && npm run build`. Node >=22. Der Server verwendet das offizielle TypeScript-SDK v2.4.0 und stdio. Beispiel für die Konfiguration im selbst gewählten MCP-Client:

```json
{
  "mcpServers": {
    "libre-ecad": {
      "command": "node",
      "args": ["/absoluter/pfad/libre-ECAD/mcp/build/index.js"],
      "env": {
        "ECAD_BACKEND_URL": "http://127.0.0.1:8185/api/company",
        "ECAD_API_TOKEN": "EINMALIGEN_PROJEKTZUGANG_HIER_EINTRAGEN"
      }
    }
  }
}
```

Die Backend-URL enthält bei direktem Firmenservice nur Host/Port (z. B. 8183), beim Web-Proxy zusätzlich `/api/company`. Tokens gehören in die private Clientkonfiguration, nicht in Git oder URLs. Requests folgen keinen Redirects, haben ein 15-Sekunden-Limit und geben keine Transport-/Credential-Dumps an das Modell zurück.

Werkzeuge: `ecad_list_projects` (offset/limit), `ecad_get_project`, `ecad_get_documents`, `ecad_propose_drawing`. Kein SQL, Git, Benutzerverwaltung, Freigabe-, Upload-, Übernahme- oder Konfliktlösungswerkzeug. Projekttexte sind Daten und keine Anweisungen. Das SDK validiert Toolargumente; der ECAD-Server validiert zusätzlich das gesamte Zeichnungsmodell.

Es wird **kein Modellanbieter automatisch verbunden**. Der Kunde entscheidet im MCP-Client über Modell, Anbieter und Datenweitergabe. Ein lokales Offline-LLM ist nicht Bestandteil dieses Servers; MCP benötigt das Firmenbackend. Quellen: [offizielles SDK](https://github.com/modelcontextprotocol/typescript-sdk), [MCP Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).

## Abnahme

- Dart: Scope-/Firmengrenzen, gesperrter Benutzer/entzogene Mitgliedschaft, read-only, Widerruf, gefälschte Bestätigung, UI-Sitzung vs. API-Zugang, konkurrierende Übernahmen, veraltete Version, kein Freigabestatus.
- `npm --prefix mcp test`: realer stdio-Handshake, Toolauflistung und Argumentvalidierung, Pagination, ausschließlich erlaubte API-Pfade, Vorschläge und bereinigte Fehlermeldungen.
- `scripts/smoke-m6.py`: echter MCP-Client gegen HTTP/PostgreSQL, Offline-Upload-Rennen, auditiertes menschliches Übernehmen, Tokenwiderruf und Neustartpersistenz. Nur synthetische M4-Testfirma.
- `scripts/browser-m6.py`: explizite Zugangsbestätigung, grafischer Vergleich, Abbruch und bewusste Übernahme in Chromium, kein Offline-Einstieg im Web.

Windows-/Android-Geräteabnahme und produktives HA sind davon getrennte, offene M6-Abnahmepunkte.

Zehn ausschließlich lesende, reproduzierbare Modell-Evaluationsfragen für die synthetische Motorabgang-Fixture liegen in `mcp/test/evaluation.xml`. Sie wurden vorbereitet; es wurde kein externer Modellanbieter aufgerufen und keine LLM-Qualitätsbewertung behauptet. `scripts/smoke-m6.py --recovery --outage` prüft zusätzlich echte SQL-Wiederherstellung aller vier Projekt-/Automationstabellen und den Ausfall des globalen Diensts mit Wiederanlauf.
