import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/screens/login_screen.dart';
import 'package:libre_ecad_app/src/session_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final role in ['admin', 'zeichner']) {
    testWidgets(
      '$role can change password from Einstellungen and is signed out',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/auth/login') {
            return http.Response(
              jsonEncode({
                'token': 'token',
                'username': 'user',
                'role': role,
                'companyName': 'Firma',
              }),
              200,
            );
          }
          if (request.url.path == '/users') {
            return http.Response(jsonEncode({'users': []}), 200);
          }
          if (request.url.path == '/me/password') {
            return http.Response(
              jsonEncode({
                'status': 'password_changed',
                'sessionsRevoked': true,
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        });
        final session = SessionService(httpClient: client);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: session,
            child: const MaterialApp(home: LoginScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Benutzername'),
          'user',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Passwort'),
          'old-password',
        );
        await tester.ensureVisible(find.text('Anmelden'));
        await tester.tap(find.text('Anmelden'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Einstellungen'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Einstellungen').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Aktuelles Passwort'),
          'old-password',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Neues Passwort'),
          'new-password-123',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Neues Passwort bestätigen'),
          'new-password-123',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Passwort ändern'));
        await tester.pumpAndSettle();
        final change = requests.singleWhere(
          (r) => r.url.path == '/me/password',
        );
        expect(change.headers['authorization'], 'Bearer token');
        expect(jsonDecode(change.body), {
          'currentPassword': 'old-password',
          'newPassword': 'new-password-123',
          'confirmPassword': 'new-password-123',
        });
        expect(session.isLoggedIn, false);
        expect(find.text('Anmelden'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'invalid confirmation stays on settings and does not send password',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'token',
              'username': 'user',
              'role': 'zeichner',
              'companyName': 'Firma',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => SessionService(httpClient: client),
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'),
        'user',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Passwort'),
        'old-password',
      );
      await tester.ensureVisible(find.text('Anmelden'));
      await tester.tap(find.text('Anmelden'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Einstellungen'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Einstellungen').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Aktuelles Passwort'),
        'old-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Neues Passwort'),
        'new-password-123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Neues Passwort bestätigen'),
        'different',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Passwort ändern'));
      await tester.pump();
      expect(find.text('Passwörter stimmen nicht überein.'), findsOneWidget);
      expect(requests.where((r) => r.url.path == '/me/password'), isEmpty);
    },
  );

  testWidgets('settings creates a user-wide LLM token once and revokes it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    var revoked = false;
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/login') {
        return http.Response(
          jsonEncode({
            'token': 'session-token',
            'username': 'user',
            'role': 'zeichner',
            'companyName': 'Firma',
          }),
          200,
        );
      }
      if (request.url.path == '/users') {
        return http.Response(jsonEncode({'users': []}), 200);
      }
      if (request.url.path == '/api/v1/automation/user-tokens' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'tokens':
                revoked ||
                    !requests.any(
                      (r) =>
                          r.url.path == '/api/v1/automation/user-tokens' &&
                          r.method == 'POST',
                    )
                ? []
                : [
                    {
                      'id': 'hash-id',
                      'label': 'Meine Assistenz',
                      'scope': 'user',
                      'expiresAt': '2027-02-01T00:00:00Z',
                      'revoked': false,
                    },
                  ],
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/automation/user-tokens' &&
          request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 'hash-id',
            'label': 'Meine Assistenz',
            'token': 'one-time-secret',
            'expiresAt': '2027-02-01T00:00:00Z',
          }),
          201,
        );
      }
      if (request.url.path == '/api/v1/automation/user-tokens/hash-id/revoke') {
        revoked = true;
        return http.Response(jsonEncode({'revoked': true}), 200);
      }
      return http.Response('{}', 404);
    });
    final session = SessionService(httpClient: client);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Benutzername'),
      'user',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passwort'),
      'password',
    );
    await tester.ensureVisible(find.text('Anmelden'));
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Einstellungen'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Einstellungen').first);
    await tester.pumpAndSettle();
    expect(find.text('LLM-Zugang für alle meine Projekte'), findsOneWidget);
    await tester.ensureVisible(find.text('LLM-Zugang erstellen'));
    await tester.tap(find.text('LLM-Zugang erstellen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Bezeichnung'),
      'Meine Assistenz',
    );
    expect(find.text('Zugang erstellen'), findsOneWidget);
    // Explicit consent is required for the full user permissions.
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.tap(find.text('Zugang erstellen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final post = requests.singleWhere(
      (r) =>
          r.url.path == '/api/v1/automation/user-tokens' && r.method == 'POST',
    );
    expect(post.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(post.body), {
      'confirmed': true,
      'label': 'Meine Assistenz',
    });
    expect(find.text('one-time-secret'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('one-time-secret'), findsNothing);
    expect(find.text('Meine Assistenz'), findsOneWidget);
    await tester.ensureVisible(find.text('Widerrufen'));
    await tester.tap(find.text('Widerrufen'));
    await tester.pumpAndSettle();
    expect(revoked, true);
    expect(find.text('one-time-secret'), findsNothing);
  });
}
