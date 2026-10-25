import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/screens/symbol_designer.dart';

void main() {
  testWidgets('draw, undo, redo and save an independent article symbol', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = symbolTemplate('coil', 'test');
    final before = canonicalJson(initial);
    Json? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Json>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SymbolDesigner(initial: initial),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linie'));
    final canvas = find.byKey(const ValueKey('symbol-designer-canvas'));
    await tester.dragFrom(
      tester.getCenter(canvas) + const Offset(120, 120),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('line 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.text('line 5'), findsNothing);
    await tester.tap(find.byTooltip('Wiederholen'));
    await tester.pumpAndSettle();
    expect(find.text('line 5'), findsOneWidget);
    await tester.tap(find.text('Symbol übernehmen'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(validateSymbol(result), result);
    expect(
      (result!['primitives'] as List).length,
      (initial['primitives'] as List).length + 1,
    );
    expect(canonicalJson(initial), before);
  });
  testWidgets('read-only and compact designer cannot save', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: SymbolDesigner(editable: false)),
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Symbol übernehmen'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(
      const MaterialApp(home: SymbolDesigner(key: ValueKey('editable'))),
    );
    tester.view.physicalSize = const Size(780, 850);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Symbol übernehmen'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Darstellung zu klein'), findsOneWidget);
  });
}
