# LibreECAD

**LibreECAD** ist ein geplantes, quelloffenes Werkzeug zur Planung und Dokumentation von Elektroanlagen – für Verteilerbau und Schaltanlagen. Der Name ist ein **Arbeitsname**; Marken- und Namensrechte wurden nicht abschließend geprüft.

> **Projektstatus:** **Meilenstein 1–4 sind für die LAN-Vorschau umgesetzt:** Firmenprojekte mit Mitgliedschaften, persönliche/Firmenartikel, Metadaten-Baukasten, Artikelhistorie, bewusste Kopien und getrennte globale Suche. M3 ergänzt moderierte Katalogbeiträge und eine getrennte Betreiberoberfläche. M4 ergänzt einen Schaltplaneditor mit expliziten elektrischen Verbindungen, mehreren Blättern und Gerätequerverweisen. Die kleine Symbolbibliothek ist synthetisch; ein grafischer Symboleditor folgt später. Öffentlicher Upload-/Mietbetrieb benötigt eine eigene fachliche Freigabe.

## Zielbild

Schaltpläne, einpolige Übersichten, Klemmen- und Ansichtszeichnungen sowie Installationspläne sollen auf einem gemeinsamen fachlichen Datenmodell beruhen. Betriebsmittel, Anschlüsse und elektrische Verbindungen sind dabei strukturierte Objekte: Eine grafische Kreuzung ist nicht automatisch ein elektrischer Knoten. Listen, Querverweise und Exporte sollen aus demselben gewählten Projektstand entstehen.

Geplant sind ein gemeinsamer globaler Artikelstamm sowie getrennte persönliche und firmeneigene Bestände. Der globale Stamm unterscheidet allgemeine Artikel, eindeutig zugeordnete Herstellerdaten und bewusst veröffentlichte Nutzerbeiträge. Herkunft, Version und Prüfstatus müssen sichtbar bleiben; ein Nutzerbeitrag wird nicht als verifizierter Herstellerdatensatz ausgegeben.

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

**Spätere Meilensteine:** Dokumentation, Plausibilitätsprüfung und unveränderliche freigegebene Projektstände; vorbereitete Offline-Arbeit in installierten Clients, Katalog-Ausfallsicherheit und fachliche API/MCP-Schnittstellen; weitere Planarten, Makros, fachlich geprüfte Berechnungen und ERP-Übergabe; zuletzt eine mehrsprachige Homepage und ein mehrsprachiges Wiki. Diese Reihenfolge ist ein Plan, keine Implementierungszusage.

## Wichtige Grenzen

- **Web benötigt ein erreichbares Firmenbackend.** Offline-Arbeit ist später nur für installierte Clients mit zuvor heruntergeladenen Projekten und Bibliotheken vorgesehen.
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

## Lizenz

Der bisherige Repository-Code steht unter der [MIT-Lizenz](LICENSE). Rechte an späteren Schaltzeichen, Normtabellen, Herstellerdaten, Nutzerbeiträgen und anderen Bibliotheksinhalten werden **gesondert** geklärt; die Softwarelizenz erteilt dafür keine pauschalen Nutzungsrechte.
