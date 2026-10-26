# Zeichenblatt und Revisionsfeld

Das Flutter-Zeichenblatt sowie die SVG- und PDF-Ausgabe zeigen einen eigenständig gestalteten Rahmen mit nummerierten Spalten, Buchstabenzonen und einem gegliederten Schriftfeld. Als gestalterische Referenz diente das allgemeine Blattkonzept von [Logickiste](https://logickiste.de/editor/index.html); weder Grafik noch JS/CSS wurden übernommen. Die Zeichenfläche und ihre Koordinaten bleiben unverändert.

Im Schriftfeld erscheinen der tatsächliche Blatttitel, Projektname, die Blattnummer/Gesamtzahl, der technische Arbeitsstand und der jeweilige Freigabestatus (Entwurf: „Nicht fachlich freigegeben“; festgeschriebenes PDF/SVG-Paket: „FACHLICH FESTGESCHRIEBEN“). Der Revisionsbereich zeigt die letzten vier **am Blatt gespeicherten** Einträge; ohne Einträge steht dort „Keine Revisionen erfasst“. Es gibt keine automatisch erfundenen Bearbeiter- oder Datumsangaben.

Über **Blatt → Revisionen bearbeiten** können Zeichner Revisionsstand, Datum im Format `JJJJ-MM-TT` und eine optionale Kurznotiz manuell anlegen, ändern oder nach Bestätigung entfernen. Bis zu 20 eindeutige Revisionen pro Blatt werden validiert und zusammen mit der Zeichnung gespeichert. Das Speichern nutzt die bestehende Projektversionsprüfung und Entwurfshistorie; der Revisionsstand ist **nicht** die technische Projektdaten-Version und keine Fachfreigabe. Bestehende Zeichnungen ohne `revisions` bleiben gültig.

Die Anzeige begrenzt sich aus Platzgründen auf vier Einträge; der Editor zeigt alle. Eintragungsreihenfolge bestimmt die Anzeige (neuester Eintrag zuletzt); das Datum wird auf ein gültiges Kalenderdatum geprüft, nicht mit dem aktuellen Tag vorbelegt.
