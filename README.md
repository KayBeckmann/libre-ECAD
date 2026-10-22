# LibreECAD

Freies, mehrbenutzerfähiges ECAD für Elektroplanung (Schaltpläne,
Verteilerbau, Installationspläne). Siehe den fachlichen Hintergrund im
Obsidian-Vault (`10_Projects/libre-ECAD/Brainstorming.md` und
`Roadmap.md`) — diese Dateien sind die verbindliche Quelle für Umfang
und Reihenfolge, nicht dieses README.

**Status:** Meilenstein 1 (belastbares Grundgerüst) im Aufbau. Noch
keine Zeichenfunktionen, keine Projekte, keine Artikel-Uploads.

## Architektur (M1)

Getrennte Docker-Container je Dienst, jeder mit eigener
Postgres-Datenbank (kein geteiltes DB-Schema zwischen Diensten):

| Dienst | Zweck | Host-Port (Compose) |
|---|---|---|
| `super-admin-service` | Kays globale Verwaltung: Firmen/Erst-Admins anlegen, Audit | 8181 |
| `global-articles-service` | Ein logisch globaler, lesbarer Artikelstamm (Allgemein/Hersteller/User-Upload) | 8182 |
| `company-users-service` | Firmen, Nutzer, Anmeldung, Rollen (Admin/Zeichner) | 8183 |
| `web` | Ausliefert den gebauten Flutter-Web-Build (nginx) | 8185 |

Host-Ports bewusst im `81xx`-Bereich statt `80xx`, um Kollisionen mit
anderen auf diesem Rechner laufenden Projekten (z. B. WerkkernERP auf
8085, saasERP auf 8081/8082) zu vermeiden. Innerhalb des
Compose-Netzes sprechen die Dienste weiterhin über ihre
Original-Ports (8081/8082/8083).

Jeder Dienst ist ein eigenständiges Dart-Programm (`shelf` +
`shelf_router`), das gegen seine **eigene** Postgres-Instanz spricht.
Installierte Flutter-Clients (Linux/Windows/Android) sind eigenständige
Clients, keine Container.

Details, Entscheidungen und offene Punkte: [`docs/architecture.md`](docs/architecture.md).

## Backend-Dienste starten

```bash
cp .env.example .env   # Secrets lokal anpassen, NIE committen
docker compose up -d --build
curl http://localhost:8181/health
curl http://localhost:8182/health
curl http://localhost:8183/health
```

## Backend-Tests (pro Dienst, ohne laufende DB)

```bash
cd backend/super_admin_service && dart test
cd backend/global_articles_service && dart test
cd backend/company_users_service && dart test
```

Die Tests laufen gegen eine In-Memory-Repository-Implementierung
(keine echte Postgres-Verbindung nötig) — siehe
`docs/architecture.md#testing`.

## Flutter-Frontend

```bash
cd frontend/libre_ecad_app
flutter run -d chrome          # Web
flutter run -d linux           # Linux Desktop
flutter build windows          # Windows (auf Windows-Host/CI)
flutter build apk --debug      # Android
```

## Lizenz

Siehe `LICENSE`. Marken-/Namensrechte für „LibreECAD" sind laut
Brainstorming **nicht abschließend geprüft** — keine öffentliche
Vermarktung ohne diese Prüfung.
