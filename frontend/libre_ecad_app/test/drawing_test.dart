import 'dart:convert';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/api/workspace_api.dart';
import 'package:libre_ecad_app/src/drawing/drawing_controller.dart';
import 'package:libre_ecad_app/src/drawing/drawing_canvas.dart';
import 'package:libre_ecad_app/src/models.dart';
import 'package:libre_ecad_app/src/screens/drawing_screen.dart';
import 'package:libre_ecad_app/src/session_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final session = Session(
    token: 'test',
    username: 'test',
    role: UserRole.zeichner,
    companyName: 'TEST',
    backendUrl: Uri.parse('http://localhost'),
  );
  testWidgets('page references are searchable and open the creation dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'projectName': 'Verweise',
            'version': 1,
            'drawing': sampleDrawing('motor'),
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Bauteil suchen'),
      'seitenverweis',
    );
    await tester.pumpAndSettle();
    final entry = find.text('Seitenverweis / Blattfortsetzung');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('Blattfortsetzung anlegen'), findsOneWidget);
    await tester.tap(find.text('Fortsetzung anlegen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nach ', skipOffstage: false), findsWidgets);
    expect(find.text('Seitenverweis hinzufügen', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    api.close();
  });
  testWidgets('Bauteil suchen findet PXL-Katalogtreffer', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final workspace = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'projectName': 'P',
            'version': 1,
            'drawing': emptyDrawing(),
          }),
          200,
        ),
      ),
    );
    final catalog = MockClient((r) async {
      expect(r.url.queryParameters['query'], 'pxl');
      return http.Response(
        jsonEncode({
          'results': [
            {
              'id': 'catalog-fiktiv-demo',
              'articleNumber': 'DEMO-236',
              'name': 'PXL-DEMO/1',
              'source': 'catalog',
              'manufacturerName': 'FIKTIV',
              'category': 'Leitungsschutzschalter',
              'symbolKey': 'mcb1',
              'version': 1,
              'origin': 'Testkatalog Seite 1',
            },
          ],
        }),
        200,
      );
    });
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionService(httpClient: catalog),
        child: MaterialApp(
          home: DrawingScreen(session: session, projectId: 'p', api: workspace),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Bauteil suchen'),
      'pxl',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PXL-DEMO/1'), findsOneWidget);
    await tester.tap(find.textContaining('PXL-DEMO/1'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO-236 · V1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    workspace.close();
    catalog.close();
  });
  test('Katalogtreffer platziert gemeinsames Symbol mit Artikelreferenz', () {
    final drawing = emptyDrawing();
    final sheet = objects(drawing, 'sheets').single['id'] as String;
    const hit = GlobalArticleSearchHit(
      id: 'catalog-fiktiv-demo',
      articleNumber: 'DEMO-236',
      name: 'PXL-DEMO/1',
      source: 'catalog',
      manufacturerName: 'FIKTIV',
      category: 'Leitungsschutzschalter',
      symbolKey: 'mcb1',
      origin: 'Testkatalog Seite 1',
      version: 1,
    );
    final instance = placeCatalogArticle(drawing, sheet, 200, 200, hit);
    expect(instance['symbol'], 'mcb1');
    final device = objectById(
      drawing,
      'devices',
      instance['deviceId'] as String,
    );
    expect(device['article']['id'], hit.id);
    expect(device['article']['number'], hit.articleNumber);
    expect(device['article']['manufacturer'], 'FIKTIV');
    expect(validateDrawing(drawing), isA<Json>());
    expect(
      () => placeCatalogArticle(
        drawing,
        sheet,
        220,
        200,
        const GlobalArticleSearchHit(
          id: 'missing',
          version: 1,
          articleNumber: '?',
          name: 'X',
          source: 'catalog',
          symbolKey: 'not-a-symbol',
        ),
      ),
      throwsFormatException,
    );
    expect(objects(drawing, 'instances'), hasLength(1));
  });
  testWidgets('wire menu accepts a free-text potential for both pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final drawing = sampleDrawing('motor');
    final api = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'projectName': 'Netze',
            'version': 1,
            'drawing': drawing,
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: api),
      ),
    );
    await tester.pumpAndSettle();
    final continuationWire = find.textContaining('TEST-Signal').first;
    await tester.ensureVisible(continuationWire);
    final tile = find.ancestor(
      of: continuationWire,
      matching: find.byType(ListTile),
    );
    final menu = find.descendant(
      of: tile,
      matching: find.byTooltip('Verbindung bearbeiten'),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potential frei eingeben / entfernen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Potential (leer = entfernen)'),
      '+24V Steuerung',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+24V Steuerung · '), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    api.close();
  });
  testWidgets('general built-ins appear in the editor palette', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'projectName': 'Palette',
            'version': 1,
            'drawing': emptyDrawing(),
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: api),
      ),
    );
    await tester.pumpAndSettle();
    final palette = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final category in [
      'Motoren',
      'Schutzgeräte',
      'Schalter / Taster',
      'Schütze / Relais',
      'Elektronik',
      'Transformatoren / Netzteile',
      'Anschlüsse / Versorgung',
    ]) {
      await tester.scrollUntilVisible(
        find.text(category),
        350,
        scrollable: palette,
      );
      expect(find.text(category), findsOneWidget);
    }
    expect(
      find.text('Schutzleiter / Erde', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Photovoltaikzelle', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  test(
    'undo restores removed instance and wires without changing identity',
    () {
      final initial = sampleDrawing('motor'),
          c = DrawingController(sampleDrawing('motor'));
      c.replace(initial);
      c.markSaved();
      final id = objects(c.drawing, 'instances').first['id'];
      c.removeInstance(id);
      expect(c.dirty, isTrue);
      expect(
        objects(c.drawing, 'instances').length,
        objects(initial, 'instances').length - 1,
      );
      c.undo();
      expect(c.drawing, initial);
      expect(c.dirty, isFalse);
      c.redo();
      expect(c.dirty, isTrue);
      c.dispose();
    },
  );
  testWidgets('sample saves and conflict cancellation preserves draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Json? saved;
    var version = 1, conflict = false, puts = 0;
    final api = WorkspaceApi(
      session,
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          puts++;
          if (conflict) {
            return http.Response(
              jsonEncode({'error': 'Stand wurde geändert.'}),
              409,
            );
          }
          saved = (jsonDecode(r.body) as Json)['drawing'];
          version++;
        }
        return http.Response(
          jsonEncode({
            'projectName': 'UI-Test',
            'version': version,
            'drawing': saved,
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Arbeitsproben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbeitsproben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST · Steuer- / Motorabgang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbeitsprobe laden'));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 Geräte'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(puts, 1);
    expect(objects(saved!, 'sheets'), hasLength(2));
    conflict = true;
    await tester.ensureVisible(find.text('Arbeitsproben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbeitsproben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST · Verteilerabgang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbeitsprobe laden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Konflikt: Arbeitsstände vergleichen'), findsOneWidget);
    await tester.tap(find.text('Entwurf behalten / abbrechen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ungespeichert'), findsOneWidget);
    expect(puts, 2);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('unavailable backend and small viewport disable editing', (
    tester,
  ) async {
    final api = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(jsonEncode({'error': 'Kein Zugriff'}), 401),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein Zugriff'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
    final shortIds = sampleDrawing('motor');
    (shortIds['nodes'] as List).add({
      'id': 'n',
      'sheetId': objects(shortIds, 'sheets').first['id'],
      'x': 400,
      'y': 400,
    });
    final available = WorkspaceApi(
      session,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'projectName': 'Small',
            'version': 1,
            'drawing': shortIds,
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(session: session, projectId: 'p', api: available),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Darstellung zu klein für Bearbeitung'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Verbinden'))
          .onSelected,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    available.close();
  });
  testWidgets(
    'connection recovery retains the draft and clears the outage message',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var available = true;
      final api = WorkspaceApi(
        session,
        client: MockClient((r) async {
          if (!available) throw Exception('TEST offline');
          return http.Response(
            jsonEncode({
              'projectName': 'Connection',
              'version': 1,
              'drawing': null,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(session: session, projectId: 'p', api: api),
        ),
      );
      await tester.pumpAndSettle();
      available = false;
      await tester.tap(find.byTooltip('Verbindung prüfen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Backend nicht erreichbar'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Speichern'),
            )
            .onPressed,
        isNull,
      );
      available = true;
      await tester.tap(find.byTooltip('Verbindung prüfen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Backend nicht erreichbar'), findsNothing);
      expect(find.textContaining('ungespeichert'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Speichern'),
            )
            .onPressed,
        isNotNull,
      );
      tester.view.physicalSize = const Size(780, 850);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Speichern'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('ungespeichert'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
