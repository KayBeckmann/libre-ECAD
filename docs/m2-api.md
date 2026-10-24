# M2 API und Betriebsgrenzen

Firmenbackend: `/api/v1`, im Compose-Webproxy unter `/api/company/api/v1`.
Alle Anfragen benötigen `Authorization: Bearer <Sitzungstoken>` des gewählten
Firmenbackends. Firma, Eigentümer und Akteur werden aus der Sitzung abgeleitet;
sie sind keine vom Client frei wählbaren Berechtigungsfelder.

| Methode / Pfad | Verhalten |
| --- | --- |
| GET /projects | Nur zugängliche Projekte |
| POST /projects | Admin: name, description, memberIds; Version 1 |
| GET /projects/:id | Admin der Firma oder zugewiesener Zeichner |
| PATCH /projects/:id | name, description, version; nur Admin darf memberIds setzen |
| GET /articles?scope=personal&query=Text | Persönlicher Stamm; scope=company für Firmenstamm |
| POST /articles | scope, articleNumber, name, origin, license, notes, layers |
| GET /articles/:id | Berechtigter Artikel mit Hinweisen auf Datenlücken |
| PATCH /articles/:id | Vollständige editierbare Artikelfelder und bekannte version |
| GET /articles/:id/history | Alle bisherigen Versionen, gleiche Leserechte wie Artikel |
| POST /articles/:id/copy | Ziel-scope und bekannte version; neue unabhängige ID |
| POST /global-articles/:id/copy | Ziel-scope und globale version; serverseitige Quellprüfung |

Antworten: 201 bei Anlage/Kopie, 200 bei Lesen/Änderung, 400 bei ungültigen Daten,
401 bei fehlender/ungültiger Sitzung, 403 bei fehlendem Schreibrecht, 404 für
unzugängliche/unbekannte IDs, 409 bei Versionskonflikt, 503 bei Katalogausfall.
Ein Konflikt führt nicht zu einem stillen Wiederholungsversuch. Entwurfseingaben
bleiben im Formular erhalten; vor erneutem Speichern den aktuellen Stand prüfen.

Artikelbeispiel (synthetisch):

```json
{
  "scope": "personal",
  "articleNumber": "TEST-001",
  "name": "Testgerät",
  "origin": "Eigener synthetischer Entwurf",
  "license": "CC0",
  "notes": "Keine Hersteller- oder Normfreigabe",
  "layers": {
    "symbol": {
      "reference": "Eigener Testblock",
      "license": "CC0",
      "terminals": [{"id": "A1", "label": "Eingang"}]
    },
    "mechanical": {"widthMm": 18, "heightMm": null, "depthMm": null},
    "electrical": {"voltageV": 24, "currentA": null},
    "thermal": {"powerLossW": null, "conditions": "Noch unbekannt"}
  }
}
```

Artikelnummern/Projektnamen sind Anzeigenamen, keine technischen Schlüssel.
IDs bleiben stabil. Ebenen-IDs bleiben bei Änderungen erhalten, eine Kopie erhält
neue Ebenen-IDs. Die Historie erfasst vollständige Snapshots, Autor und UTC-Zeitpunkt.
Es gibt noch keine Lösch-/Archivfunktion, keine fachliche Freigabe, keinen
Symbolgeometrieeditor, keine PDF-Ausgabe, kein Git-Projektformat und keinen Sync.
Dafür gelten die späteren Roadmap-Entscheidungstore.

Globaler Dienst: `/articles?query=Text&source=general|manufacturer|userUpload`;
optional `manufacturer=ACME` (exakter Name, unabhängig von Groß-/Kleinschreibung).
Antworten behalten ID, Herkunft, Hersteller und Version. Der Testkatalog enthält
keine verifizierten Herstellerdaten. Importe ändern keine Rechte oder Herkunft.

## LAN-Vorschau

`./scripts/build-web.sh` und danach `docker compose up -d --build` im Repo.
Der Build liefert Flutter-Webressourcen lokal aus (`--no-web-resources-cdn`),
damit ein reiner LAN-Betrieb nicht am externen Render-CDN hängt.
Der Webzugriff erfolgt über `http://<Host-im-LAN>:8185`. Standardbackend und
Katalog werden relativ zu diesem Host ermittelt. Native Apps benötigen eine
passende Backendadresse. Nicht benötigte Browser-CORS-Freigaben werden nicht
pauschal geöffnet. Superadmin-API: Port 8181, separates Frontend folgt in M3.
Bootstrap-Zugang steht ausschließlich in der ignorierten `.env`; lokale
Vorschauzugänge können in `.local-access.json` (ignoriert, Modus 0600) liegen.
Datenbanken bleiben ausschließlich im Compose-Netz. Die LAN-Vorschau verwendet
HTTP; der dokumentierte TLS-/Anmeldeschutz für Internetbetrieb ist weiterhin offen.

## Noch zu entscheiden

- Archivieren/Löschen und Aufbewahrung von Projekt-/Artikelhistorien.
- Übergabe persönlicher Artikel bei Ausscheiden, Publikationsvorschläge von Zeichnern.
- Artikelarten, Varianten, Datenblätter, Einheiten jenseits des M2-Minimums.
- Granulare Projektrechte, freigebende Personen und Prüferrolle vor M5.
- Seitengrößen, Suchpagination und Lastbudgets vor großen realen Katalogen.
- Konkrete Normtexte, Symbollizenzen und fachliche Datenprüfung vor realer Nutzung.
