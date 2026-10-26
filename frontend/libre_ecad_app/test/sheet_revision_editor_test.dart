import 'dart:convert';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/api/workspace_api.dart';
import 'package:libre_ecad_app/src/models.dart';
import 'package:libre_ecad_app/src/screens/drawing_screen.dart';

void main() {
  testWidgets('sheet revisions can be added, edited, removed and saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = Session(
      token: 'test',
      username: 'test',
      role: UserRole.zeichner,
      companyName: 'TEST',
      backendUrl: Uri.parse('http://localhost'),
    );
    Json drawing = emptyDrawing();
    var version = 1;
    final api = WorkspaceApi(
      session,
      client: MockClient((request) async {
        if (request.method == 'PUT') {
          drawing = (jsonDecode(request.body) as Json)['drawing'] as Json;
          version++;
        }
        return http.Response(
          jsonEncode({
            'projectName': 'Revisionstest',
            'version': version,
            'drawing': drawing,
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
    await tester.tap(find.byTooltip('Revisionen bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Revisionen erfasst'), findsOneWidget);
    await tester.tap(find.text('Revision hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Revisionsstand'),
      'A',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Datum (JJJJ-MM-TT)'),
      '2025-02-29',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Ungültige Revision'), findsOneWidget);
    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Revisionen erfasst'), findsOneWidget);
    await tester.tap(find.text('Revision hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Revisionsstand'),
      'A',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Datum (JJJJ-MM-TT)'),
      '2025-03-17',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Kurznotiz (optional)'),
      'Erstprüfung',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A · 2025-03-17'), findsOneWidget);
    await tester.tap(find.byTooltip('Revision A bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Revisionsstand'),
      'B',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B · 2025-03-17'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(objects(drawing, 'sheets').first['revisions'], [
      {'revision': 'B', 'date': '2025-03-17', 'note': 'Erstprüfung'},
    ]);
    await tester.tap(find.byTooltip('Revisionen bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Revision B entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revision entfernen'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Revisionen erfasst'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(objects(drawing, 'sheets').first['revisions'], isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
