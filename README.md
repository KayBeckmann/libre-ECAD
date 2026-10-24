# LibreECAD

[Deutsch](Readme-de.md)

**LibreECAD** is a planned open-source tool for designing and documenting electrical installations, distribution boards, and control panels. The name is a **working title**; trademark and naming rights have not been fully checked.

> **Project status:** **Milestones 1–3 are implemented for LAN testing:** company projects with memberships, personal/company article libraries, a metadata builder, version history, deliberate copies and separate global search. M3 adds moderated public contributions and a separate operator console. There is still **no CAD editor or graphical symbol editor**. Public commercial operation requires separate process approval.

## Vision

Schematics, single-line diagrams, terminal and assembly drawings, and installation plans should share one engineering data model. Devices, terminals, and electrical connections are structured objects: two lines crossing on a drawing do not automatically form an electrical junction. Lists, cross-references, and exports should all be generated from the same selected project revision.

A shared global article catalog and separate personal and company catalogs are planned. The global catalog will distinguish general articles, data submitted by authorized manufacturers, and contributions deliberately published by users. Provenance, version, and verification status must remain visible; a user contribution must never be presented as verified manufacturer data.

## Development sequence

The **first milestone** is intentionally limited to a foundation, built in this order:

1. **Super-admin backend:** Protected access for creating a company account and its first company admin. — **Implemented** (`backend/super_admin_service`).
2. **Global article backend:** A separate service with a basic article model and search using clearly labeled sample data. Moderated contributions were added in M3. — **Implemented** (`backend/global_articles_service`).
3. **Company/user backend:** Sign-in and user management within each company. Initially there are only two roles: **Admin** and **Drafter**; neither role grants access across companies. — **Implemented** (`backend/company_users_service`).
4. **Flutter frontend:** Select a company backend (the project operator's managed backend is the editable default), sign in, and show a minimal role-appropriate screen. There is no CAD editor in this milestone. — **Implemented** (`frontend/libre_ecad_app`; web, Linux and Android builds verified, Windows build needs a Windows host/runner).

The three backend services each use a separate PostgreSQL instance; the web delivery runs in its own nginx container. Installed Flutter apps are not containers. Details, test strategy, and open follow-ups: [`docs/architecture.md`](docs/architecture.md).

**Milestone 2:** Projects and memberships are isolated per company. Personal articles stay private; company articles are readable by company members and editable by admins. Changes use version checks; copies retain their source version and evolve independently. Technical layers distinguish missing values from zero and stay unverified. API and operational details: [`docs/m2-api.md`](docs/m2-api.md).

**Milestone 3:** Deliberate public previews, moderation, immutable releases and withdrawals; assigned manufacturer identities; a separate operator console with audited company access, contracts and manual payment records. See [`docs/m3-operations.md`](docs/m3-operations.md).

**Later milestones:** An electrical CAD editing core; documentation, consistency checks, and immutable approved project revisions; prepared offline work in installed clients, catalog resilience, and domain-level API/MCP interfaces; additional drawing types, macros, professionally validated calculations, and ERP integration; finally, a multilingual website and wiki. This is a plan, not a claim that any of these features have been implemented.

## Important boundaries

- **The web app requires a reachable company backend.** Offline work is planned only for installed clients with previously downloaded projects and libraries.
- **Conflicts are never resolved automatically.** Affected changes require an active decision by an authorized user.
- **External CAD data** will be accepted only as non-editable image references, not imported as native project objects.
- **No DIN VDE compliance is claimed.** Applicable standard editions, licensing, reference cases, and professional review must be resolved before making credible calculation or compliance claims.
- A distributed global catalog with a write leader and read replicas is **an architecture idea to evaluate**, not an implemented high-availability system. A technical quorum cannot verify the engineering correctness of article data.

## Running the local LAN stack

```bash
cp .env.example .env   # fill in local secrets, never commit this file
./scripts/build-web.sh  # local Flutter renderer assets; no render CDN needed
docker compose up -d --build
curl http://localhost:8181/health   # super-admin-service
curl http://localhost:8182/health   # global-articles-service
curl http://localhost:8183/health   # company-users-service
```

Open `http://<LAN-host>:8185`. The browser uses the same host for its backend and catalog proxy. Super-admin credentials bootstrap from `.env`; the separate operator UI runs at `http://<LAN-host>:8186`. The company app requires a company account.

Backend tests (per service, no running database needed):

```bash
cd backend/super_admin_service && dart test
```

Frontend:

```bash
cd frontend/libre_ecad_app
flutter run -d chrome   # or -d linux / flutter build apk --debug
```

Full details, port rationale, and the request flow (super-admin creates a company and its first admin, who activates their account, signs in, and creates a drafter) are in [`docs/architecture.md`](docs/architecture.md). Please do not post real project data or credentials in issues.

## License

The repository's software is covered by the [MIT License](LICENSE). Rights for future schematic symbols, standards tables, manufacturer data, user contributions, and other library content must be clarified **separately**; the software license does not grant blanket rights to those materials.
