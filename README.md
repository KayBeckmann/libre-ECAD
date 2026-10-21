# LibreECAD

[Deutsch](Readme-de.md)

**LibreECAD** is a planned open-source tool for designing and documenting electrical installations, distribution boards, and control panels. The name is a **working title**; trademark and naming rights have not been fully checked.

> **Project status:** Concept stage. This repository does **not yet contain a working application**. The features below are goals, not currently available functionality.

## Vision

Schematics, single-line diagrams, terminal and assembly drawings, and installation plans should share one engineering data model. Devices, terminals, and electrical connections are structured objects: two lines crossing on a drawing do not automatically form an electrical junction. Lists, cross-references, and exports should all be generated from the same selected project revision.

A shared global article catalog and separate personal and company catalogs are planned. The global catalog will distinguish general articles, data submitted by authorized manufacturers, and contributions deliberately published by users. Provenance, version, and verification status must remain visible; a user contribution must never be presented as verified manufacturer data.

## Development sequence

The **first milestone** is intentionally limited to a foundation, built in this order:

1. **Super-admin backend:** Protected access for creating a company account and its first company admin.
2. **Global article backend:** A separate service with a basic article model and search using clearly labeled sample data. Public uploads come later.
3. **Company/user backend:** Sign-in and user management within each company. Initially there are only two roles: **Admin** and **Drafter**; neither role grants access across companies.
4. **Flutter frontend:** Select a company backend (the project operator's managed backend is the editable default), sign in, and show a minimal role-appropriate screen. There is no CAD editor in this milestone.

The M1 services and web-frontend delivery are planned as separate Docker containers. Installed Flutter apps are not containers.

**Later milestones:** Projects and personal/company articles with an article builder; authorized global contributions and manufacturer management; an electrical CAD editing core; documentation, consistency checks, and immutable approved project revisions; prepared offline work in installed clients, catalog resilience, and domain-level API/MCP interfaces; additional drawing types, macros, professionally validated calculations, and ERP integration; finally, a multilingual website and wiki. This is a plan, not a claim that any of these features have been implemented.

## Important boundaries

- **The web app requires a reachable company backend.** Offline work is planned only for installed clients with previously downloaded projects and libraries.
- **Conflicts are never resolved automatically.** Affected changes require an active decision by an authorized user.
- **External CAD data** will be accepted only as non-editable image references, not imported as native project objects.
- **No DIN VDE compliance is claimed.** Applicable standard editions, licensing, reference cases, and professional review must be resolved before making credible calculation or compliance claims.
- A distributed global catalog with a write leader and read replicas is **an architecture idea to evaluate**, not an implemented high-availability system. A technical quorum cannot verify the engineering correctness of article data.

## Installation and contributing

There is no build, installation guide, or production access yet. Please do not post real project data or credentials in issues. Requirements and architecture can be discussed in GitHub issues; executable development instructions will follow when implementation begins.

## License

The repository's software is covered by the [MIT License](LICENSE). Rights for future schematic symbols, standards tables, manufacturer data, user contributions, and other library content must be clarified **separately**; the software license does not grant blanket rights to those materials.
