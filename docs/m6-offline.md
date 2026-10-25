# M6.1 – vorbereitete Offline-Arbeit

Installierte Clients zeigen im Projekt „Offline vorbereiten“ und auf Login/Arbeitsplatz „Offlineprojekte“. Bewusster Download benötigt aktuelle Projektberechtigung und einen gespeicherten Zeichnungsstand. Ein separates lokales Passwort (mindestens acht Zeichen) schützt die gesamte Ablage mit AES-256-GCM und PBKDF2-HMAC-SHA256 (210.000 Iterationen, zufälliges Salt). Serverpasswort und Sitzung werden nicht abgelegt. Bibliotheksversion und lokale Revision gehören zur verschlüsselten Kopie. Originalschriftarten liegen im App-Bundle; PDF benötigt keinen Font-Download.

Die Standardberechtigung läuft 24 Stunden ab Download/Erneuerung (`OFFLINE_LEASE_HOURS`, 1–168). Danach bleiben Änderungen gespeichert, bis derselbe Benutzer seine aktuellen Rechte online bestätigt. Ein offline getrenntes Gerät kann nicht sofort durch den Server gesperrt werden. Ablauf- und Rückstellprüfung sind Clientregeln, kein Schutz gegen einen Gerätebesitzer, der Programm oder Uhr gezielt manipuliert. Der Server akzeptiert Uploads unabhängig davon nur mit aktueller Anmeldung, Firmen-/Projektberechtigung und unverändertem Vergleichsstand.

„Vergleichen und hochladen“ meldet sich neu an, zeigt beide Zeichnungen und verlangt eine Entscheidung. Die Serverfassung kann die lokale Kopie ersetzen oder die lokale Zeichnung als neuer Server-Arbeitsstand gespeichert werden. Eine weitere Änderung während des Vergleichs führt zu 409; keine automatische Wiederholung/Übernahme. Servermetadaten bleiben erhalten. Die Historie enthält Benutzer, ursprüngliche Basis und verglichenen Serverstand. Ein Upload erteilt keine Freigabe.

Der bestehende Zeichenkern und derselbe PDF-Renderer laufen serverseitig und nativ. Offline-PDFs tragen **OFFLINE-ENTWURF – NICHT FREIGEGEBEN**. Kleine Fenster bleiben wie im Web schreibgeschützt. Web hat keine Offline-Ablage; der native Einstieg fehlt dort vollständig.

Die Datei liegt im plattformeigenen Application-Support-Verzeichnis unter `offline/vault.json`. Atomisches Ersetzen, exklusives Dateilock und Vergleich des vorherigen verschlüsselten Inhalts verhindern unbemerktes Überschreiben durch ein zweites Fenster. Unix-Verzeichnis/Datei: 0700/0600; Windows nutzt das Benutzerprofil. Keine zusätzliche Klartextkopie anlegen. Ein vergessenes lokales Passwort lässt sich nicht zurücksetzen; vorhandene Serverstände können neu heruntergeladen werden.

## Ausgeführte Prüfungen, 2026-10-25

- Backend: Rechte, fremde Firma/Identität, fehlende Bestätigung, konkurrierender Upload (ein 200/ein 409), Rechteentzug und Audit.
- Flutter: Verschlüsselungs-Roundtrip, falsches Passwort, Manipulation, lokale konkurrierende Änderung, Ablauf/Zeit-Rückstellung, inkompatible Bibliothek, lokale Zeichnungsänderung/PDF und gesperrte Freigabe.
- Linux Release-Build und gestarteter Linux-Integrationstest unter isoliertem Xvfb: echte verschlüsselte Datei, erneutes Öffnen, Zeichenoberfläche, lokale Änderung und PDF bei blockiertem Dart-HTTP. Test nutzt ausschließlich eigenes `XDG_DATA_HOME` mit Präfix `libre-ecad-native-test-`.
- Android-Debug-APK erfolgreich gebaut; Windows-Build sowie Windows-/Android-Geräteabnahme stehen aus. Ein Linux-Test ist kein Nachweis für deren Dateisystem-/Druckdialoge.

Reproduktion: `flutter analyze`, `flutter test` im App-Verzeichnis; `DISPLAY=:97 XDG_DATA_HOME=/tmp/libre-ecad-native-test-<lauf> flutter test integration_test/offline_native_test.dart -d linux` mit vorbereitetem virtuellem Display. Der Test exportiert `offline-acceptance.pdf` in dieses Testverzeichnis. Kein echter Benutzer-Vault wird verwendet.

Android: Release benötigt HTTPS; die INTERNET-Berechtigung ist im Hauptmanifest. Nur Debug erlaubt zusätzlich HTTP für die private LAN-Entwicklung. Linux-Bundle: `frontend/libre_ecad_app/build/linux/x64/release/bundle/`; Android-Debug: `frontend/libre_ecad_app/build/app/outputs/flutter-apk/app-debug.apk`. Builds sind lokale Artefakte, keine veröffentlichten Releases.
