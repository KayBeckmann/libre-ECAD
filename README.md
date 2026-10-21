# LibreECAD

**LibreECAD** ist ein geplantes, quelloffenes Werkzeug zur Planung und Dokumentation von Elektroanlagen – für Verteilerbau und Schaltanlagen. Der Name ist ein **Arbeitsname**; Marken- und Namensrechte wurden nicht abschließend geprüft.

> **Projektstatus:** Konzeptphase. Dieses Repository enthält derzeit noch **keine lauffähige Anwendung**. Die nachstehenden Funktionen beschreiben Ziele, nicht bereits verfügbare Produktfunktionen.

## Zielbild

Schaltpläne, einpolige Übersichten, Klemmen- und Ansichtszeichnungen sowie Installationspläne sollen auf einem gemeinsamen fachlichen Datenmodell beruhen. Betriebsmittel, Anschlüsse und elektrische Verbindungen sind dabei strukturierte Objekte: Eine grafische Kreuzung ist nicht automatisch ein elektrischer Knoten. Listen, Querverweise und Exporte sollen aus demselben gewählten Projektstand entstehen.

Geplant sind ein gemeinsamer globaler Artikelstamm sowie getrennte persönliche und firmeneigene Bestände. Der globale Stamm unterscheidet allgemeine Artikel, eindeutig zugeordnete Herstellerdaten und bewusst veröffentlichte Nutzerbeiträge. Herkunft, Version und Prüfstatus müssen sichtbar bleiben; ein Nutzerbeitrag wird nicht als verifizierter Herstellerdatensatz ausgegeben.

## Entwicklungsfolge

Der **erste Meilenstein** ist bewusst auf ein Grundgerüst begrenzt und wird in dieser Reihenfolge entwickelt:

1. **Super-Admin-Backend:** Geschützter Zugang; Firmenzugang und erstes Firmen-Admin-Konto anlegen.
2. **Globales Artikelbackend:** Eigenständiger Dienst mit Artikel-Basismodell und Suche anhand gekennzeichneter Testdaten. Öffentliche Uploads folgen später.
3. **Firmen-/Nutzerbackend:** Anmeldung und Benutzerverwaltung innerhalb der eigenen Firma. Zunächst nur **Admin** und **Zeichner**; kein firmenübergreifender Zugriff.
4. **Flutter-Frontend:** Firmenbackend auswählen (Managed-Backend des Projektbetreibers als änderbare Voreinstellung), anmelden und die für die Rolle passende minimale Ansicht öffnen. Noch kein CAD-Editor.

Die M1-Dienste und die Auslieferung des Web-Frontends sind als getrennte Docker-Container vorgesehen. Installierte Flutter-Anwendungen sind keine Container.

**Spätere Meilensteine:** Projekte und persönliche/Firmenartikel mit Artikel-Baukasten; berechtigte globale Beiträge und Herstellerverwaltung; ECAD-Zeichenkern; Dokumentation, Plausibilitätsprüfung und unveränderliche freigegebene Projektstände; vorbereitete Offline-Arbeit in installierten Clients, Katalog-Ausfallsicherheit und fachliche API/MCP-Schnittstellen; weitere Planarten, Makros, fachlich geprüfte Berechnungen und ERP-Übergabe; zuletzt eine mehrsprachige Homepage und ein mehrsprachiges Wiki. Diese Reihenfolge ist ein Plan, keine Implementierungszusage.

## Wichtige Grenzen

- **Web benötigt ein erreichbares Firmenbackend.** Offline-Arbeit ist später nur für installierte Clients mit zuvor heruntergeladenen Projekten und Bibliotheken vorgesehen.
- **Konflikte werden nicht automatisch entschieden.** Betroffene Änderungen erfordern eine aktive Entscheidung eines berechtigten Nutzers.
- **Fremde CAD-Daten** sollen ausschließlich als nicht editierbare Bildvorlage übernommen werden, nicht als native Projektobjekte.
- **DIN-VDE-Konformität wird nicht behauptet.** Normausgaben, Nutzungsrechte, Referenzfälle und fachliche Abnahme müssen vor belastbaren Berechnungs- oder Konformitätsaussagen geklärt werden.
- Ein verteilter globaler Katalog mit Schreib-Leader und Lesereplikaten ist eine **zu prüfende Architekturidee**, kein implementiertes Hochverfügbarkeitssystem. Ein technisches Quorum prüft keine elektrotechnischen Artikeldaten fachlich.

## Installation und Mitwirkung

Es gibt aktuell noch keinen Build, keine Installationsanleitung und keine produktiven Zugangsdaten. Bitte keine echten Projektdaten oder Zugangsdaten für Testzwecke in Issues veröffentlichen. Beiträge zu Anforderungen und Architektur können über GitHub-Issues besprochen werden; ausführbare Entwicklungsanweisungen folgen erst mit der Implementierung.

## Lizenz

Der bisherige Repository-Code steht unter der [MIT-Lizenz](LICENSE). Rechte an späteren Schaltzeichen, Normtabellen, Herstellerdaten, Nutzerbeiträgen und anderen Bibliotheksinhalten werden **gesondert** geklärt; die Softwarelizenz erteilt dafür keine pauschalen Nutzungsrechte.
