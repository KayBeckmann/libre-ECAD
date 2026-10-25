import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/screens/planning_screen.dart';
import 'package:libre_ecad_app/src/screens/calculations_screen.dart';

void main() {
  testWidgets(
    'plan setup renders safely and compact viewport disables committing changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = emptyDrawing();
      await tester.pumpWidget(
        MaterialApp(
          home: PlanningScreen(
            drawing: d,
            sheetId: objects(d, 'sheets').first['id'],
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Installationsplan'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Planung übernehmen'),
            )
            .onPressed,
        isNotNull,
      );
      tester.view.physicalSize = const Size(780, 850);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Planung übernehmen'),
            )
            .onPressed,
        isNull,
      );
      expect(d.containsKey('plans'), isFalse);
    },
  );
  testWidgets(
    'incomplete calculation displays no fabricated result and input dialog opens',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = emptyDrawing()
        ..['calculations'] = [
          {
            'id': 'c',
            'name': 'TEST fehlende Daten',
            'kind': 'voltage',
            'source': '',
            'conditions': '',
            'phase': 'balanced3',
            'inputs': <String, dynamic>{},
          },
        ];
      await tester.pumpWidget(
        MaterialApp(home: CalculationsScreen(drawing: d, editable: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('UNVOLLSTÄNDIG – kein Ergebnis'), findsOneWidget);
      await tester.tap(find.text('Leitung / Spannungsfall'));
      await tester.pumpAndSettle();
      expect(find.text('Datenquelle / Hersteller / Revision'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
    },
  );
}
