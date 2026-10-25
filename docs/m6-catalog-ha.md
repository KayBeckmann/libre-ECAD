# M6.2 – Ausfallziel und überprüftes Katalog-Labor

## Ziel vor Produktauswahl

Ein einziger logischer globaler Katalog; genau ein Schreib-Leader. Ziel: **RPO 0 für dem Aufrufer bestätigte Schreibvorgänge bei einem einzelnen Knotenausfall**. Ein abgebrochener oder zeitlich abgelaufener Aufruf hat einen unbekannten Ausgang und muss anhand seiner fachlichen Request-ID nachgelesen werden. Kein blindes Wiederholen einer Publikation. Ohne Quorum, bestätigten Replikationsstand oder wirksames Fencing werden Schreibvorgänge gesperrt. Ein technisches Quorum ersetzt keine Artikelprüfung.

Drei unabhängige Fehlerdomänen und eine Mehrheitsentscheidung sind Voraussetzung für eine spätere automatische Wahl. Kandidaten müssen den bestätigten Datenstand besitzen. Der isolierte Alt-Leader muss **vor** einer Promotion nachweisbar am Schreiben gehindert werden; ein abgelaufener Lease oder fehlender Ping allein genügt nicht. Wiederbeitritt ausschließlich nach Datenabgleich/Neuaufbau als lesendes Replikat. Für angezeigte/veröffentlichte Versionsstände verlangen wir einen ausreichend aufgeholten Leser; ein hinterherhinkendes Replikat wird aus der Lastverteilung genommen. Die zulässige Differenz zum bestätigten angefragten Stand beträgt null. Ein RTO-SLA wird erst nach Messung auf unabhängigen Hosts festgelegt.

## Ausgeführtes Experiment (2026-10-25)

`python3 labs/catalog-ha/acceptance.py` startet drei echte PostgreSQL-16-Container in einem eigenen internen Docker-Netz, ohne veröffentlichte Ports. Es nutzt nur anonyme Testvolumes und räumt genau diese Container/Volumes/dieses Netz im `finally` auf. Die produktähnlichen Compose-Dienste bleiben unberührt. Trust-Authentifizierung gilt ausschließlich in diesem flüchtigen Testnetz.

Geprüft wurden:

1. Ein Leader, zwei lesende Streaming-Replikate; beide enthalten den mit `remote_apply` bestätigten Datensatz. Direkte Schreibversuche an Replikaten scheitern.
2. Netztrennung des Leaders. Ein weiterer Schreibaufruf bleibt nachweislich in PostgreSQL `SyncRep` hängen und wird nicht erfolgreich bestätigt. **Der alte Leader ist dabei weiterhin lokal ein Primary.** Quorum allein verhindert also keine zweite Schreibinstanz.
3. Die Labor-Steuerung verweigert Promotion ohne Quorum, aufgeholten Kandidaten und Fence-Nachweis (32 Kombinationen der Vorbedingungen). Diese Prüfung ist ein Entscheidungsmodell, kein implementierter verteilter Konsensdienst.
4. Explizites Stoppen des alten Containers und Prüfung seines gestoppten Zustands vor Promotion. Der unbestätigte Aufruf endet mit Fehler. Bestätigte Daten bleiben auf dem neuen Leader erhalten.
5. Neues synchrones Replikat, erfolgreich bestätigter weiterer Datensatz. Der alte Leader wird im Labor aus einem neuen Basebackup aufgebaut und kommt ausschließlich als lesendes Replikat zurück. Seine unbestätigte Abzweigung wird nicht veröffentlicht.

Ergebnis: **PASS**, zwei bestätigte Datensätze erhalten, alter Leader read-only, 32 Vorbedingungen geprüft. Gemessener manueller Umschaltabschnitt: **6,72 Sekunden**, gesamter Test **19,46 Sekunden**. Das ist eine lokale Labormessung, kein zugesichertes RTO. Vor dem Fehler wartet das Labor auf beide Replikate; nach dem nachgewiesenen Fencing auf das verbleibende Replikat. Diese strengere Einstellung macht den Datenstand der Kandidaten nachvollziehbar und senkt bewusst die Schreibverfügbarkeit.

## Offene Betriebsabnahme

Der laufende globale Katalog bleibt beim bestehenden einzelnen PostgreSQL. Es wurde **kein automatisch failoverfähiger Produktionscluster** installiert. Noch erforderlich: Produkt-/Betriebsentscheidung für Konsens und unabhängiges Fencing, getrennte Hosts, Strom-/Prozessstillstand und asymmetrische Partitionen, Promotion-/Rejoin-Automation, Lastverteiler und messbare Readiness/LSN-Regeln. Die heutige Katalog-API verwendet für `Records` auch lesend eine Transaktion mit Advisory-Lock; sie darf nicht unverändert an ein physisch schreibgeschütztes Replikat gehängt werden. Diese Änderung und deren End-to-End-Abnahme bleiben ein ausdrücklicher M6-Restpunkt.

Ein Cluster, dessen drei Instanzen auf demselben Rechner laufen, überlebt keinen Ausfall dieses Rechners. Ein Docker-Stop im Labor ersetzt keinen unabhängigen Hardware-Watchdog/STONITH im Betrieb. Die Produktion darf unbestätigte Daten beim Rejoin nur nach dokumentierter Sicherungs-/Rewind-Entscheidung verwerfen.

Quellen zur Architekturentscheidung: [PostgreSQL 16: Streaming/synchrone Replikation](https://www.postgresql.org/docs/16/warm-standby.html), [Patroni: Replikationsmodi](https://patroni.readthedocs.io/en/latest/replication_modes.html), [Patroni: Watchdog und Lease/Fencing-Grenzen](https://patroni.readthedocs.io/en/latest/watchdog.html). Patroni ist damit ein geprüfter Kandidat, keine beschlossene oder eingesetzte Produktwahl.
