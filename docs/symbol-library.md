# Eingebaute Schaltsymbole: Herkunft und Grenzen

Die allgemeinen, global eingebauten Symbole enthalten eigenständig entworfene Vektorglyphen unter der MIT-Lizenz des Repositories. Sie sind keine Firmen-, Artikel- oder Normsymbolbibliothek. Die bestehenden Symbol-IDs bleiben erhalten; die Siemens-basierten funktionalen Ergänzungen liegen in **Grundschaltungen**, weitere allgemeine Ergänzungen in **Schutzgeräte**, **Antriebe / Energie**, **Elektronik** und **Anschlussklemmen**.

Als reine Bedarfsreferenz für **funktionale Themen** diente [Siemens CM1N0113E, „Grafische Symbole für Elektroschema“](https://sid.siemens.com/v/u/20002), Ausgabe 1998, © Siemens Building Technologies Ltd. Weder dessen Grafiken noch Dokumenttext wurden übernommen; ein Recht zur Wiederverwendung des Dokuments ist nicht belegt. Die PDF liegt nicht im Repository. Die hier gezeichneten Vektoren sind unabhängig erstellt. Es wird keine IEC-Konformität, Vollständigkeit oder Austauschbarkeit mit Herstellerunterlagen zugesagt.

Neu enthalten: Schutzleiter-/Erdungsanschluss, Sicherung, Widerstand, Kondensator, Diode, LED, Batterie, Transformator (getrennte Primär-/Sekundäranschlüsse), Lampe, Taster Schließer/Öffner, Umschalter (COM/NO/NC), Summer/Hupe, Volt- und Amperemeter sowie Photovoltaikzelle. Vorhandene Relais-, Versorgungs-, Motor-, Schutz-, Automatisierungs- und Artikelsymbole bleiben bestehen. Polare Bauteile führen `P`/`N` als technische Port-IDs (Anzeige `+`/`−`); Dioden führen `A`/`K`.

Nicht enthalten: mechanische Verbindung / Betätigungs-Kopplung. Das aktuelle Modell kennt nur **elektrische** Ports, Drähte und Netze. Eine mechanische Kopplung als zweipoliges Bauteil würde fälschlich eine elektrische Verbindung suggerieren. Ebenso sind keine speziellen Herstellerartikel, exakte Normvarianten oder kompletten Kataloge enthalten. Die Symbole dienen schematischer Darstellung, nicht Sicherheitsauslegung.

## Logickiste-Registry: funktionaler Abgleich (53 Einträge)

Referenz: https://logickiste.de/editor/index.html — nur Namen, Kategorien und Varianten als Bedarfsinventar verglichen; kein fremder JS-/SVG-Code übernommen. Zuordnung ist funktional, nicht grafische oder Norm-Parität. Vorhanden bedeutet bereits vor dieser Erweiterung (einschließlich uncommittierter Siemens-Arbeit), neu bedeutet in dieser Erweiterung ergänzt. Abgegrenzt benennt Varianten oder Produktspezifika ohne exakte Entsprechung.

| Referenzgruppe | Registry-Key / Variante | Status | libreECAD / Grenze |
|---|---|---|---|
| kontakt | `hauptkontakt` (poles=3, hubbel=true) | abgegrenzt | `breaker3` ist ein Schutzgerät, kein Hauptkontakt |
| kontakt | `schuetz` | vorhanden | `coil` |
| kontakt | `taster` (subtype=no) | vorhanden | `push_no` |
| kontakt | `schalter` (subtype=no) | vorhanden | `switch` |
| kontakt | `schliesser` | vorhanden | `contact` |
| kontakt | `oeffner` | vorhanden | `contact_nc` |
| verbraucher | `umformer_ac_ac` | neu | `converter_ac_ac` |
| verbraucher | `umformer_ac_dc` | neu | `converter_ac_dc` |
| verbraucher | `netzteil_ac_dc_din` | neu | `psu_pe` |
| verbraucher | `3_phasen_motor` | vorhanden | `motor` |
| verbraucher | `dahlander_motor_6_terminals` | neu | `motor_6terminal` |
| verbraucher | `lampe` | vorhanden | `lamp` |
| verbraucher | `gleichstrom_motor` | neu | `motor_dc` |
| verbraucher | `wechselstrom_motor_1ph` | neu | `motor_1ph` |
| verbraucher | `heizwiderstand` | neu | `heater` |
| klemmen | `klemme` (terminals=1) | vorhanden | `terminal` |
| klemmen | `pfeil_raus` | abgegrenzt | Fortsetzungspunkt (Ausgangsrichtung nur visuell) |
| klemmen | `pfeil_rein` | abgegrenzt | Fortsetzungspunkt (Eingangsrichtung nur visuell) |
| sicherungen | `leitungsschutzschalter_1_polig` | neu | `mcb1` |
| sicherungen | `leitungsschutzschalter_2_polig` | neu | `mcb2` |
| sicherungen | `leitungsschutzschalter_3_polig` | neu | `mcb3` |
| sicherungen | `Schmelzsicherung` | vorhanden | `fuse` |
| sicherungen | `motorschutzschalter` | neu | `motor_protection` |
| sicherungen | `fi_schutzschalter_2_polig` | neu | `rcd2` |
| sicherungen | `fi_schutzschalter_4_polig` | neu | `rcd4` |
| sicherungen | `fi_ls_schalter_2_polig` | neu | `rcbo2` |
| sicherungen | `fi_ls_schalter_4_polig` | neu | `rcbo4` |
| potenziale | `pot_1phase` (potPhases=1) | abgegrenzt | supply (keine eigenständige Potenzial-Phasenfunktion) |
| potenziale | `pot_2phase` (potPhases=2) | abgegrenzt | keine 2-Phasen-Variante |
| potenziale | `pot_3phase` (potPhases=3) | abgegrenzt | supply3 (keine Phasenvariante der Potenzialfortsetzung) |
| elektronik | `widerstand` | vorhanden | `resistor` |
| elektronik | `poti` | neu | `potentiometer` |
| elektronik | `ldr` | neu | `ldr` |
| elektronik | `kondensator` | vorhanden | `capacitor` |
| elektronik | `diode` | vorhanden | `diode` |
| elektronik | `led_elektronik` | vorhanden | `led` |
| elektronik | `npn_transistor` | neu | `transistor_npn` |
| elektronik | `pnp_transistor` | neu | `transistor_pnp` |
| elektronik | `triac` | neu | `triac` |
| elektronik | `diac` | neu | `diac` |
| elektronik | `leerfeld_4` | neu | `ic4` |
| elektronik | `leerfeld_6` | neu | `ic6` |
| elektronik | `leerfeld_8` | neu | `ic8` |
| elektronik | `leerfeld_10` | neu | `ic10` |
| elektronik | `arduino_uno` | abgegrenzt | produktspezifisches Board |
| elektronik | `arduino_r4` | abgegrenzt | produktspezifisches Board |
| elektronik | `arduino_nano` | abgegrenzt | produktspezifisches Board |
| elektronik | `netzteil_ac_dc` | neu | `converter_ac_dc` (gemeinsame AC/DC-Umformer-Glyphe) |
| elektronik | `relais_modul` | abgegrenzt | PCB-Modul, kein allgemeines Relais |
| elektronik | `summer` | vorhanden | `buzzer` |
| elektronik | `printklemme_2` | neu | `pcb_terminal2` |
| elektronik | `batterie_zelle` | vorhanden | `battery` |
| elektronik | `batterie_gefuellt` | abgegrenzt | battery (keine Füllstil-Variante) |

Ergebnis: 15 vorhanden, 27 neu, 11 abgegrenzt; **keine Behauptung eines vollständigen Variantenabgleichs**. `hauptkontakt` fehlt als dedizierter Hauptkontakt (das bestehende `breaker3` ist ein Schutzgerät). `dahlander_motor_6_terminals` entspricht nur einem generischen Motor mit sechs getrennten Klemmen; keine Dahlander-Verschaltungslogik. Die `continuations` des Datenmodells sind bereits als signalbenannte Verbindungspunkte im Editor verfügbar; Eingangs-/Ausgangspfeile sowie 1-/2-/3-Phasen-Potenzialvarianten werden nicht als elektrische Bauteile erfunden. Mehrpolige Schutzgeräte zeigen gekoppelte Kontakte und Funktionskennungen schematisch; Schutzkennlinien, Auslöseverhalten und Normkonformität werden nicht modelliert.
