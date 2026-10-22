# LibreECAD – Architektur-Entscheidungen M1

Interne Entwicklerdokumentation, bewusst ab M1 begonnen (Roadmap-Vorgabe
für M8: „interne Entwicklerdokumentation bereits ab M1, nicht erst
hier beginnen"). Dieses Dokument hält **technische** Entscheidungen
fest, die die Roadmap/das Brainstorming bewusst offengelassen haben
(„Server- und Datenbankwahl im Detail bleibt offen"). Fachliche/
rechtliche Entscheidungstore aus der Roadmap bleiben unberührt und sind
dort, nicht hier, zu klären.

## Technologiewahl

- **Backend-Sprache: Dart** (Roadmap-Vorgabe: „Backend passend zu
  Flutter in Dart"). Framework: **`shelf` + `shelf_router`**, bewusst
  statt eines größeren Full-Stack-Frameworks (z. B. Serverpod) — drei
  schlanke, unabhängige Dienste mit wenigen Endpunkten profitieren
  mehr von Transparenz/Kontrolle über jede Zeile als von generierten
  Codegen-Schichten, die für dieses Grundgerüst Overkill wären. Spätere
  Migration auf ein größeres Framework bleibt möglich, verändert aber
  die HTTP-Verträge nicht.
- **Datenbank: PostgreSQL**, eine **eigene Instanz pro Dienst**
  (`super-admin-db`, `global-articles-db`, `company-users-db`) — passt
  zur Roadmap-Vorgabe „Datenbank-/Koordinationsdienste ebenfalls
  getrennt" und verhindert, dass ein Dienst versehentlich Tabellen
  eines anderen lesen/ändern kann. Zugriff über das offizielle
  `postgres`-Pub-Paket (parametrisierte SQL, kein ORM) — bei drei
  Diensten mit wenigen Tabellen bringt ein ORM keinen Vorteil, nur
  zusätzliche Abstraktionsschicht.
- **Kein Migrationsframework in M1:** jeder Dienst führt beim Start
  idempotente `CREATE TABLE IF NOT EXISTS`-Anweisungen aus
  (`lib/src/db/schema.dart`). Für M1 mit noch keinem Produktivbetrieb
  ausreichend; ein echtes Migrationswerkzeug (z. B. `dart_migrator`,
  eigene SQL-Dateien mit Versionstabelle) ist vor M2 nachzuziehen,
  sobald Schemaänderungen gegen echte Bestandsdaten laufen müssen —
  gleiches Prinzip wie WerkkernERPs versionierte Drift-Migrationen,
  nur noch nicht in M1 gebraucht.
- **Passwort-Hashing:** `bcrypt`-Pub-Paket. **Sitzungen:** opake,
  zufällige Tokens (256 Bit, `dart:math` `Random.secure()`), serverseitig
  nur als Hash gespeichert (`sha256`), Ablaufzeit je Sitzung — bewusst
  **kein JWT**: ein serverseitig gespeichertes Token lässt sich sofort
  und zuverlässig widerrufen (Sperren/Deaktivieren), ein JWT ohne
  Revocation-Liste nicht. Übertragung als `Authorization: Bearer <token>`.
- **Dienst-zu-Dienst-Aufruf (Super-Admin → Firmen-/Nutzerdienst):**
  gemeinsames Secret `INTERNAL_SERVICE_TOKEN` (Umgebungsvariable, nie
  committet) als `X-Internal-Token`-Header auf einem eigenen,
  **nicht** öffentlich beworbenen `/internal/*`-Pfad. Für M1
  ausreichend; vor Internet-Exposition (Managed-Hosting) gehört dieser
  Pfad hinter ein internes Docker-Netz ohne Port-Mapping nach außen
  (siehe `docker-compose.yml`: die `*-service`-Container exponieren nur
  die öffentlichen Ports, der interne Aufruf läuft über den
  Compose-eigenen DNS-Namen im selben Netz).

## Testing

Jeder Dienst definiert sein Repository als **Interface**
(`lib/src/repository.dart`) mit zwei Implementierungen:

- `InMemory*Repository` — für `dart test`, keine Datenbank nötig,
  schnell und deterministisch (gleiches Prinzip wie WerkkernERPs
  `AppDatabase.forTesting()` mit In-Memory-SQLite, nur hier als
  reines Dart-Objekt statt einer echten DB).
- `Postgres*Repository` — für den echten Betrieb.

HTTP-Handler (`lib/src/router.dart`) bekommen das Repository injiziert
und werden in Tests gegen die In-Memory-Variante über echte
`shelf`-Requests geprüft (`shelf_router` + `http` testweise aufrufen,
kein Mocking von Dart-Funktionen nötig). Das deckt Rollenprüfung,
Firmentrennung und Fehlerfälle ab, ohne eine Postgres-Instanz im
Testlauf zu benötigen. Der volle Dienst inkl. echter Postgres-Anbindung
wird über `docker compose` manuell/als Abnahme geprüft (siehe
Roadmap-Abnahmekriterien je Unterpunkt).

## Testing-Fallstricke (gefunden während M1)

- **`SharedPreferences.getInstance()` hängt unter `flutter_test`
  unbegrenzt**, wenn nicht vorher `SharedPreferences.
  setMockInitialValues({})` aufgerufen wurde (bekannte
  Plattformgrenze der `shared_preferences`-Testintegration, kein
  Produktionsbug) — jeder Widget-Test, der `LoginScreen` pumpt, muss
  das vorher tun (siehe `test/login_flow_test.dart`).
- **`flutter_test` blockiert jeden echten `HttpClient`**, auch mit
  `tester.runAsync()`. Deshalb sind alle API-Clients
  (`CompanyUsersApi`/`GlobalArticlesApi`) über einen injizierbaren
  `http.Client` gebaut — Widget-Tests übergeben ein `MockClient`
  (`package:http/testing.dart`) über `SessionService(httpClient: ...)`
  statt gegen echte, über `docker compose` laufende Dienste zu
  testen. Der echte Beweis gegen Postgres-gestützte Dienste läuft über
  die `dart test`-Suiten der Backend-Dienste (dort ohne jede
  Einschränkung) sowie manuell über `docker compose` + `curl`.

## Plattform-Build-Status M1

- **Web, Linux, Android:** auf diesem Linux-Entwicklungsrechner
  gebaut und verifiziert (`flutter build web/linux/apk`).
- **Windows:** kann von einem Linux-Host aus **nicht** gebaut werden
  (Flutter braucht für den Windows-Build-Schritt einen echten
  Windows-Host oder einen Windows-CI-Runner). Noch nicht verifiziert —
  vor M1-Endabnahme auf einem Windows-Rechner oder in einer
  Windows-GitHub-Actions-Runner-Pipeline nachholen. Der Flutter-Code
  selbst enthält keine plattformspezifischen Pfade, die das verhindern
  würden (reines `http`/`provider`/`shared_preferences`, keine
  nativen Plugins).

## Offene, bewusst vertagte Punkte (nicht M1-blockierend)

- Erstzugang-Zustellung: Super-Admin erzeugt aktuell einen
  Aktivierungslink als **Klartext-Antwort auf den API-Aufruf** (kein
  SMTP-Dienst existiert noch) — Kay gibt ihn dem Firmen-Admin manuell/
  außerhalb der App. Vor echtem Managed-Betrieb durch einen
  Versandweg ersetzen (sobald E-Mail/Benachrichtigung existiert).
- Keine Rate-Limits/Brute-Force-Schutz auf `/auth/login` in M1 —
  vor Internet-Exposition nachziehen.
- Kein TLS innerhalb des Docker-Netzes (Compose-intern); vor
  Produktionsbetrieb hinter einen Reverse Proxy mit TLS stellen.
