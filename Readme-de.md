# LibreECAD

**LibreECAD** ist ein quelloffenes Werkzeug in Entwicklung zur Planung und Dokumentation von Elektroanlagen – für Verteilerbau und Schaltanlagen. Der Name ist ein **Arbeitsname**; Marken- und Namensrechte wurden nicht abschließend geprüft.

> **Projektstatus:** Die Entwicklungsfunktionen aus M1–M8 sind für private LAN-Tests verfügbar: Firmenprojekte und Rollen, Artikel-/Symboldesigner, Drehstrompläne und verknüpfte Relaiskontakte, versionierte Dokumente, vorbereitete native Offline-Arbeit, API/MCP sowie Installations-/Aufbauplanung. M8 ergänzt eine deutsch-/englischsprachige Homepage und ein versioniertes Wiki in getrennten Containern sowie einen geprüften Linux-Entwicklungsdownload. Die Oberfläche folgt den [Projektmockups](docs/mockups/README.md). Fachabnahme, Windows-/Android-Geräteprüfung, produktives HA und öffentlicher kommerzieller Betrieb bleiben offen.

## Zielbild

Schaltpläne, einpolige Übersichten, Klemmen- und Ansichtszeichnungen sowie Installationspläne sollen auf einem gemeinsamen fachlichen Datenmodell beruhen. Betriebsmittel, Anschlüsse und elektrische Verbindungen sind dabei strukturierte Objekte: Eine grafische Kreuzung ist nicht automatisch ein elektrischer Knoten. Listen, Querverweise und Exporte sollen aus demselben gewählten Projektstand entstehen.

Umgesetzt sind ein gemeinsamer globaler Artikelstamm sowie getrennte persönliche und firmeneigene Bestände. Der globale Stamm unterscheidet allgemeine Artikel, eindeutig zugeordnete Herstellerdaten und bewusst veröffentlichte Nutzerbeiträge. Herkunft, Version und Prüfstatus müssen sichtbar bleiben; ein Nutzerbeitrag wird nicht als verifizierter Herstellerdatensatz ausgegeben.

## Entwicklungsfolge

Der **erste Meilenstein** ist bewusst auf ein Grundgerüst begrenzt und wird in dieser Reihenfolge entwickelt:

1. **Super-Admin-Backend:** Geschützter Zugang; Firmenzugang und erstes Firmen-Admin-Konto anlegen. — **Umgesetzt** (`backend/super_admin_service`).
2. **Globales Artikelbackend:** Eigenständiger Dienst mit Artikel-Basismodell und Suche anhand gekennzeichneter Testdaten. Moderierte Beiträge wurden in M3 ergänzt. — **Umgesetzt** (`backend/global_articles_service`).
3. **Firmen-/Nutzerbackend:** Anmeldung und Benutzerverwaltung innerhalb der eigenen Firma. Zunächst nur **Admin** und **Zeichner**; kein firmenübergreifender Zugriff. — **Umgesetzt** (`backend/company_users_service`).
4. **Flutter-Frontend:** Firmenbackend auswählen (Managed-Backend des Projektbetreibers als änderbare Voreinstellung), anmelden und die für die Rolle passende minimale Ansicht öffnen. Noch kein CAD-Editor. — **Umgesetzt** (`frontend/libre_ecad_app`; Web-, Linux- und Android-Build verifiziert, Windows-Build braucht einen Windows-Host/-Runner).

Die drei Backenddienste nutzen jeweils eine eigene PostgreSQL-Instanz; das Web-Frontend wird in einem separaten nginx-Container ausgeliefert. Installierte Flutter-Anwendungen sind keine Container. Details, Testkonzept und offene Punkte: [`docs/architecture.md`](docs/architecture.md).

**Meilenstein 2:** Projekte und Mitgliedschaften sind firmengetrennt. Persönliche Artikel bleiben privat; Firmenartikel sind firmenweit lesbar und durch Admins bearbeitbar. Änderungen prüfen die bekannte Version; Kopien behalten ihre Quellversion und entwickeln sich unabhängig weiter. Technische Ebenen unterscheiden fehlende Werte von null und bleiben ungeprüft. API und Betriebsdetails: [`docs/m2-api.md`](docs/m2-api.md).

**Meilenstein 3:** Bewusste öffentliche Vorschau, Moderation, Freigabe- und Rückzugshistorie, Herstellerzuordnung sowie eine getrennte Betreiberverwaltung für Zugänge, Verträge und manuelle Zahlungsbelege. Details: [`docs/m3-operations.md`](docs/m3-operations.md).

**Meilenstein 4:** Symbole platzieren/verschieben, Anschlüsse verbinden/trennen, Blätter, Knoten, Fortsetzungen und Kabeladern verwalten. Gerätekennungen und Querverweise bleiben konsistent. Atomare Projektversionen, Rückgängig/Wiederholen, Historie und bewusste Konfliktentscheidung. Einstieg: Projekt öffnen → **Schaltplan öffnen**. Details: [`docs/m4-drawing.md`](docs/m4-drawing.md).

**Meilenstein 5:** Abgeleitete Listen, Metadaten-Deckblätter, explizite PDF-Quellen, objektbezogene Prüffunde und begründete Freigaben mit unveränderlichen Git-/SQL-Paketen. Details: [Dokumente und Freigaben](docs/m5-documents.md).

**Meilenstein 6 in Arbeit:** Verschlüsselte vorbereitete Offline-Projekte, lokales PDF und ausdrücklicher Konflikt-Upload; Linux offline getestet, Android-Debug-Build vorhanden. Projektbezogene API-/MCP-Zugänge legen Vorschläge zur menschlichen Prüfung an. Ein echtes PostgreSQL-Labor prüft Replikation, Netztrennung und Fencing. Windows-/Android-Geräteabnahme und betriebliches Katalog-HA bleiben offen. Details: [Offline](docs/m6-offline.md), [API/MCP](docs/m6-api-mcp.md), [HA-Labor und Grenzen](docs/m6-catalog-ha.md).

**Schaltplan-Erweiterung:** Eigene Artikelsymbole zeichnen, als feste Version im Projekt verwenden, L1/L2/L3/N/PE darstellen und mehrere Öffner/Schließer einer Spule zuordnen. Anleitung: [Symboldesigner und Relaiskontakte](docs/symbol-designer.md).

**Meilenstein 7 – Entwicklungsstand:** Installationspläne mit Bildvorlage, Maßstab und Leitungswegen; Aufbauzeichnungen nach Artikelmaßen; versionierte Makros; nachvollziehbare Rechenvorschläge und Materialübergabe. [Bedienung und Abnahmegrenzen](docs/m7-planning.md). Die WerkkernERP-Vorschau liegt auf einem getrennten Integrationszweig. Fachliche Modell-/Rechenabnahme bleibt offen.

**Meilenstein 8 – Entwicklungsstand:** Homepage und versioniertes Wiki auf Deutsch/Englisch in unabhängigen Containern, klarer Betriebs-/Buildstatus, lokale Suche und geprüfter Linux-Download. [Betrieb und ausgeführte Abnahme](docs/m8-sites.md); [Pflege der Seiten](sites/README.md). Öffentlicher Livegang benötigt weiterhin Kays Freigabe.

## Wichtige Grenzen

- **Web benötigt ein erreichbares Firmenbackend.** Vorbereitete Offline-Arbeit ist im installierten Client verfügbar; der Linux-Ablauf wurde geprüft.
- **Konflikte werden nicht automatisch entschieden.** Betroffene Änderungen erfordern eine aktive Entscheidung eines berechtigten Nutzers.
- **Fremde CAD-Daten** sollen ausschließlich als nicht editierbare Bildvorlage übernommen werden, nicht als native Projektobjekte.
- **DIN-VDE-Konformität wird nicht behauptet.** Normausgaben, Nutzungsrechte, Referenzfälle und fachliche Abnahme müssen vor belastbaren Berechnungs- oder Konformitätsaussagen geklärt werden.
- Ein verteilter globaler Katalog mit Schreib-Leader und Lesereplikaten ist eine **zu prüfende Architekturidee**, kein implementiertes Hochverfügbarkeitssystem. Ein technisches Quorum prüft keine elektrotechnischen Artikeldaten fachlich.

## Web-Stack im LAN starten

```bash
cp .env.example .env   # lokale Secrets eintragen, diese Datei nie committen
./scripts/build-web.sh  # Flutter-Renderressourcen lokal, kein Render-CDN nötig
docker compose up -d --build
curl http://localhost:8181/health   # super-admin-service
curl http://localhost:8182/health   # global-articles-service
curl http://localhost:8183/health   # company-users-service
```

Webzugriff: `http://<LAN-Host>:8185`. Backend und Katalog werden im Browser am selben Host angesprochen. Der Superadmin wird aus `.env` initialisiert; sein separates Verwaltungsfrontend läuft auf `http://<LAN-Host>:8186`. Für die ECAD-Web-App ist ein Firmenkonto erforderlich.

Backend-Tests (je Dienst, ohne laufende Datenbank):

```bash
cd backend/super_admin_service && dart test
```

Frontend:

```bash
cd frontend/libre_ecad_app
flutter run -d chrome   # oder -d linux / flutter build apk --debug
```

Alle Details, die Port-Begründung und der Ablauf (Super-Admin legt Firma + Erst-Admin an, dieser aktiviert sich, meldet sich an und legt einen Zeichner an) stehen in [`docs/architecture.md`](docs/architecture.md). Bitte keine echten Projektdaten oder Zugangsdaten in Issues veröffentlichen.

## Homepage und Wiki als Vorschau

```bash
docker compose -p libre-ecad-sites -f compose.sites.yml up -d --build
```

Einstieg: `http://127.0.0.1:8187/de/` und `http://127.0.0.1:8188/de/m8-dev/start/`; beide bieten Englisch. Die Container benötigen keine App-/Backenddienste. Private LAN-Bindung und feste Origins: siehe [M8](docs/m8-sites.md).

## Lizenz

Der bisherige Repository-Code steht unter der [MIT-Lizenz](LICENSE). Rechte an späteren Schaltzeichen, Normtabellen, Herstellerdaten, Nutzerbeiträgen und anderen Bibliotheksinhalten werden **gesondert** geklärt; die Softwarelizenz erteilt dafür keine pauschalen Nutzungsrechte.
