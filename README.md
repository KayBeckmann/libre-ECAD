# LibreECAD

[Deutsch](Readme-de.md)

**LibreECAD** is a planned open-source tool for designing and documenting electrical installations, distribution boards, and control panels. The name is a **working title**; trademark and naming rights have not been fully checked.

> **Project status:** **Milestones 1–5 are implemented for LAN testing:** company projects with memberships, personal/company article libraries, a metadata builder, version history, deliberate copies and separate global search. M3 adds moderated public contributions and a separate operator console. M4 adds a schematic editor with explicit electrical connections, multiple sheets and device cross-references. M5 adds derived lists, explicit PDF sources, plausibility findings and immutable approved Git packets. The interface follows the original [project mockups](docs/mockups/README.md). The article builder includes a graphical symbol editor; three-phase drawings and multiple NO/NC contacts per relay are supported. The built-in symbol library remains synthetic. Public commercial operation requires separate process approval.

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

**Milestone 4:** Place and move symbols, connect/disconnect terminals, manage sheets, explicit junctions and continuations, cable cores, consistent device identifiers and cross-references. Atomic project versions, undo/redo, history and explicit conflict decisions. Open a project and choose **Schaltplan öffnen**. Details: [`docs/m4-drawing.md`](docs/m4-drawing.md).

**Milestone 5:** Derived lists and metadata cover sheets, version-selected PDF export, object-linked findings, justified exceptions and explicit admin approval. Approved packets retain exact PDFs and pinned library data in SQL history and real Git commits. Open **Dokumente und Freigabe** in the editor. Details: [`docs/m5-documents.md`](docs/m5-documents.md).

**Milestone 6 in progress:** Encrypted prepared offline projects with explicit conflict upload, local PDF generation and a tested Linux client; project-scoped API/MCP credentials with human-reviewed drawing proposals. A real PostgreSQL replication/partition/fencing lab is included. Windows/Android device acceptance and operational catalog HA remain open. See [offline](docs/m6-offline.md), [API/MCP](docs/m6-api-mcp.md), and [HA experiment and limits](docs/m6-catalog-ha.md).

**Drawing extension:** Create vector symbols in the article builder, pin a version into a project, draw L1/L2/L3/N/PE, and assign multiple NO/NC contacts to one coil with shared identifiers and separate terminals. See [symbol designer and relay workflow](docs/symbol-designer.md).

**Milestone 7 development:** Raster installation plans, scale and routes, article-sized layouts, versioned macros, transparent calculation estimates and material exchange previews. See [M7 workflows and acceptance limits](docs/m7-planning.md). The WerkkernERP preview lives on a separate integration branch; professional model/calculation review remains open.

**Later:** Multilingual website and wiki.

## Important boundaries

- **The web app requires a reachable company backend.** Prepared offline work is available in installed clients; Linux offline execution is verified.
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
