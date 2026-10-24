import 'dart:convert';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/api/workspace_api.dart';
import 'package:libre_ecad_app/src/drawing/drawing_controller.dart';
import 'package:libre_ecad_app/src/models.dart';
import 'package:libre_ecad_app/src/screens/drawing_screen.dart';

void main() {
  final session = Session(
    token: 'test',
    username: 'test',
    role: UserRole.zeichner,
    companyName: 'TEST',
    backendUrl: Uri.parse('http://localhost'),
  );
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
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
