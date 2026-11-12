import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/screens/login_screen.dart';
import 'package:libre_ecad_app/src/session_service.dart';
import 'package:libre_ecad_app/src/workspace_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Shell hält die Bereichsnavigation sichtbar, während Bereiche
/// ihre eigenen Seiten öffnen, und sie bleibt für Semantik/Screenreader
/// erreichbar. Letzteres ist nicht selbstverständlich: Der ModalBarrier
/// jeder Route im verschachtelten Navigator blockiert sonst die Semantik
/// der zuvor gezeichneten Seitenleiste (in Chromium reproduziert).
void main() {
  // Der Projektbereich nutzt `WorkspaceApi` mit eigenem HTTP-Client, den
  // `flutter_test` grundsätzlich blockiert; sein Öffnen zeigt sich daher
  // an Kopfzeile und Fehlerhinweis, nicht an einer Mock-Antwort.
  final projectsPage = find.widgetWithText(AppBar, 'Projekte');

  Future<void> signIn(WidgetTester tester, {required double width}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/auth/login':
          return http.Response(
            jsonEncode({
              'token': 'tok',
              'username': 'admin-a',
              'role': 'admin',
              'companyName': 'Firma A',
            }),
            200,
          );
        case '/users':
          return http.Response(jsonEncode({'users': <Object?>[]}), 200);
      }
      return http.Response('nicht gefunden', 404);
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
      'admin-a',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'x');
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
  }

  testWidgets('wide: sidebar stays while a section opens its pages and '
      'is reachable through semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await signIn(tester, width: 1600);
    expect(find.byType(WorkspaceShell), findsOneWidget);
    expect(find.text('ELEKTROPLANUNG'), findsOneWidget);
    // Bereiche werden erst beim Öffnen aufgebaut.
    expect(projectsPage, findsNothing);

    final tile = find.widgetWithText(ListTile, 'Projekte');
    final data = tester.getSemantics(tile).getSemanticsData();
    expect(data.label, 'Projekte');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(projectsPage, findsOneWidget);
    expect(find.text('Erneut laden'), findsOneWidget);
    // Seitenleiste bleibt sichtbar; der Arbeitsplatz bleibt aufgebaut.
    expect(find.text('ELEKTROPLANUNG'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Artikelbibliothek'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('wide: sidebar can be hidden and restored without losing page', (
    tester,
  ) async {
    await signIn(tester, width: 1600);
    await tester.tap(find.widgetWithText(ListTile, 'Projekte'));
    await tester.pumpAndSettle();
    expect(projectsPage, findsOneWidget);
    await tester.tap(find.byTooltip('Menüleiste ausblenden'));
    await tester.pumpAndSettle();
    expect(find.text('ELEKTROPLANUNG'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Artikelbibliothek'), findsNothing);
    expect(projectsPage, findsOneWidget);
    await tester.tap(find.byTooltip('Menüleiste einblenden'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Artikelbibliothek'), findsOneWidget);
    expect(projectsPage, findsOneWidget);
  });

  testWidgets('narrow: bottom navigation instead of a sidebar', (tester) async {
    await signIn(tester, width: 800);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('ELEKTROPLANUNG'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Projekte'),
      ),
    );
    await tester.pumpAndSettle();
    expect(projectsPage, findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
