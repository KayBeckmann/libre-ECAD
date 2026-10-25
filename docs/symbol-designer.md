# Artikelsymbole, Drehstrom und Relaiskontakte

Ergänzung vom 25.10.2026. Die offenen Geräte-/Betriebsabnahmen von M6 bleiben
unabhängig davon bestehen.

## Artikel-Symboldesigner

Artikelbibliothek → persönlichen Artikel oder bearbeitbaren Firmenartikel öffnen
→ **Schaltsymbol erstellen/bearbeiten**. Linien, Rechtecke und Kreise werden im
Raster gezogen; Text und Anschlusspunkte per Klick gesetzt. Rechts ein Element
wählen, anschließend im Raster verschieben oder entfernen. Rückgängig/Wiederholen
steht bereit. Vorlagen enthalten auch Relaisspule, Öffner, Schließer, dreipoliges
Schutzgerät und Dreiphaseneinspeisung.

**Symbol übernehmen** übernimmt den Entwurf in das Artikelformular; anschließend
**Artikel speichern**. Namen, Funktion, Kennbuchstaben und Anschlüsse gehören zum
Symbol. Anschlusspunkte brauchen eindeutige IDs und Positionen. Relaisfunktionen
verwenden A1/A2, 13/14 oder 21/22 als logische Vorlagenanschlüsse. Ein Artikel
enthält derzeit eine Symboldefinition. Weitere Symbolvarianten können als eigene
Artikel/Kopien angelegt werden. Lizenz und Herkunft werden weiterhin am Artikel
angegeben. Firmenartikel sind nur für Admins bearbeitbar.

Im Schaltplan **Artikelsymbol einfügen** wählen und anschließend auf das Blatt
klicken. Die konkrete Artikelversion einschließlich Geometrie, Anschlüssen,
Herkunft und Symbollizenz wird in das Projekt kopiert. Änderungen am Ursprungsartikel
verändern bestehende Pläne nicht. Eine neuere Version kann zusätzlich eingefügt
werden. Eingebettete Symbole sind auch im vorbereiteten Offline-Projekt verfügbar;
neue Artikel werden online aus dem persönlichen oder Firmenstamm übernommen.

Es werden geprüfte Vektordaten gespeichert, kein ausführbares SVG oder externer
Bildverweis. Grenzen: ±120 Zeichnungseinheiten, Raster 10, 32 Anschlüsse und
128 Geometrieelemente je Symbol, 100 eingebettete Definitionen je Projekt; die
bestehende Größenbegrenzung der Zeichnungs-API gilt zusätzlich. Kleine Ansichten
zeigen den Designer ohne Bearbeitungsmöglichkeit.

## Dreiphasige Darstellung

Die Bibliotheksgruppe **Drehstrom** enthält eine Einspeisung mit L1/L2/L3/N/PE
und ein dreipoliges Schutzgerät mit sechs einzeln verdrahtbaren Anschlüssen.
Der Motor besitzt U/V/W/PE. Im Verbindungsmenü lässt sich jeder Leitung eine
Kennzeichnung L1, L2, L3, N oder PE geben oder diese entfernen.

**Arbeitsproben → TEST · Dreiphasen und Relaiskontakte** lädt einen zweiblättrigen
Beispielplan mit Motorabgang und einer Spule mit drei zugeordneten Kontakten.
Das Laden ersetzt den aktuellen Entwurf nach Bestätigung. Sich widersprechende
Leiterkennzeichnungen innerhalb eines explizit verbundenen Netzes erzeugen einen
Prüfhinweis. Die Kennzeichnung simuliert keine elektrische Funktion.

## Spule und Kontakte zuordnen

Eine Relaisspule platzieren. In deren Eigenschaften über **Weitere Darstellung…**
einen Schließer oder Öffner wählen und auf demselben oder einem anderen Blatt
platzieren. Beliebig weitere Kontakte können innerhalb der allgemeinen
Projektgrenzen folgen. Spule und Kontakte teilen Geräte-ID, BMK und Querverweise;
jeder Kontakt erhält eigene Anschlusspole, beispielsweise 13/14, 21/22, 33/34.

Ein bereits separat platzierter Kontakt kann über **Spule zuordnen / ändern**
nachträglich zugeordnet werden. Bestehende Leitungen und Darstellungs-IDs bleiben
erhalten; ihre Endpunkte wechseln auf die neuen Anschlüsse am Zielrelais.
Rückgängig stellt die vorherige Zuordnung wieder her. Ein Kontakt ohne dargestellte
Spule erzeugt einen Prüfhinweis. Mehrere Spulendarstellungen derselben physischen
Spule bleiben aus Kompatibilitätsgründen möglich und werden ebenfalls angezeigt.

Öffner und Schließer unterscheiden sich in Funktion und Zeichnung. Die Darstellung
modelliert Anschlussidentität und Dokumentation; sie führt keine Schaltsimulation
oder automatische leitende Verbindung durch Spule, Kontakte oder Schutzgeräte aus.

## Ausgabe und Prüfung

Canvas und PDF verwenden dieselben Symbolgeometrien und Anschlusszuordnungen.
Leiterkennzeichnungen erscheinen in der Zeichnung und Verbindungsliste. Die PDF
führt eingebettete Artikelsymbole mit Quellversion, Herkunft und Lizenz auf.
Alte Schema-1-Pläne und vorbereitete Offline-Pakete der ersten Bibliotheksversion
bleiben lesbar.

Reproduzierbare Prüfung:

```bash
(cd backend/ecad_core && dart analyze && dart test)
(cd backend/company_users_service && dart analyze && dart test)
(cd frontend/libre_ecad_app && flutter analyze && flutter test)
# Testfirma vorbereiten, falls noch kein /tmp/libre-ecad-m4-state.json existiert:
python3 scripts/smoke-m4.py
python3 scripts/smoke-symbols.py
python3 scripts/browser-symbols.py
```

Die Smoke-Skripte verwenden ausschließlich gekennzeichnete Testdaten. Zugangsdaten
liegen im temporären Zustandsfile mit Modus 0600. Der Browsertest zeichnet im
Artikeldesigner, speichert den Artikel, fügt die Version in einen Plan ein, ordnet
den Kontakt blattübergreifend einer Spule zu und lädt ein PDF herunter.

Abnahme am 25.10.2026: 15 Core-, 27 Firmenbackend- und 13 Flutter-Tests bestanden;
statische Analysen ohne Befunde. Live-API/PostgreSQL und Chromium-Ablauf bestanden.
Web-Release, Linux-Release und Android-Debug-Build erfolgreich. Windows und echte
Android-Geräte wurden für diese Erweiterung nicht geprüft.
