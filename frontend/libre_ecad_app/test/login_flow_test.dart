import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/screens/login_screen.dart';
import 'package:libre_ecad_app/src/session_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M1.4-Abnahme: "Durchgehender Weg Kay legt Firma und Firmen-Admin an
/// → Admin meldet sich an → legt Zeichner an → ... → Rollen- und
/// Firmengrenzen halten" — hier auf Höhe des Frontends geprüft: die
/// echte `LoginScreen`/`HomeScreen`-UI gegen ein `MockClient` (siehe
/// `package:http/testing.dart`), **kein** echter Netzwerkaufruf.
///
/// Bewusst **kein** Live-Aufruf gegen die über `docker compose`
/// laufenden Dienste: `flutter_test` blockiert jeden echten
/// `HttpClient` grundsätzlich (bekannte Plattformgrenze, kein
/// Produktionsbug) — der volle End-to-End-Beweis gegen echte
/// Postgres-gestützte Dienste läuft stattdessen über die Dart-
/// `dart test`-Suiten der drei Backend-Dienste (siehe
/// `backend/*/test/router_test.dart`) sowie manuell über
/// `docker compose` + `curl` (siehe `docs/architecture.md`).
void main() {
  Future<void> pumpAppWithClient(WidgetTester tester, http.Client client) async {
    // `LoginScreen` lädt beim Start die zuletzt gewählte Backend-URL
    // über SharedPreferences — ohne Mock-Initialisierung hängt
    // `SharedPreferences.getInstance()` unter `flutter_test`
    // unbegrenzt (bekannte Plattformgrenze, kein Produktionsbug).
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionService(httpClient: client),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Admin meldet sich an und sieht Firmenname, Rolle und die eigene Benutzerverwaltung',
    (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/auth/login') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['username'], 'admin-a');
          expect(body['password'], 'geheim123');
          return http.Response(
            jsonEncode({'token': 'tok-1', 'username': 'admin-a', 'role': 'admin', 'companyName': 'Firma A'}),
            200,
          );
        }
        if (request.url.path == '/users') {
          return http.Response(jsonEncode({'users': <Object?>[]}), 200);
        }
        return http.Response('nicht gefunden', 404);
      });

      await pumpAppWithClient(tester, client);

      await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'admin-a');
      await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'geheim123');
      await tester.tap(find.text('Anmelden'));
      await tester.pumpAndSettle();

      expect(find.text('Firma A'), findsOneWidget);
      expect(find.textContaining('Angemeldet als admin-a'), findsOneWidget);
      expect(find.text('Zeichner anlegen'), findsOneWidget, reason: 'Admin sieht die Benutzerverwaltung');
    },
  );

  testWidgets(
    'Zeichner meldet sich an und sieht nur den Hinweis auf den späteren Zeichenbereich, '
    'keine Benutzerverwaltung',
    (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'tok-2',
              'username': 'zeichner-a',
              'role': 'zeichner',
              'companyName': 'Firma A',
            }),
            200,
          );
        }
        return http.Response('nicht gefunden', 404);
      });

      await pumpAppWithClient(tester, client);

      await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'zeichner-a');
      await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'geheim123');
      await tester.tap(find.text('Anmelden'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Schaltplaneditor'), findsOneWidget);
      expect(find.text('Zeichner anlegen'), findsNothing);
    },
  );

  testWidgets('Falsches Passwort zeigt die Serverfehlermeldung, kein stiller Fehlschlag', (tester) async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'error': 'Benutzername oder Passwort falsch.'}), 401);
    });

    await pumpAppWithClient(tester, client);

    await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'admin-a');
    await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'falsch');
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();

    expect(find.text('Benutzername oder Passwort falsch.'), findsOneWidget);
  });
}
