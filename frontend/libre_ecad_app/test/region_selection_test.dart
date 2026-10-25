import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/drawing/drawing_canvas.dart';

void main() {
  testWidgets(
    'drag rectangle over a symbol selects region without moving the device',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
      addSymbol(d, 'coil', sid, 200, 200);
      Rect? region;
      var moved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawing: d,
              sheetId: sid,
              projectName: 'Selection',
              version: 1,
              selected: null,
              editable: true,
              selectingRegion: true,
              onRegion: (value) => region = value,
              onTap: (_) {},
              onSelect: (_) {},
              onMove: (_, _) => moved = true,
              onPort: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Fit is 1; the canvas has 20 pixels of padding. Start on the symbol itself.
      await tester.dragFrom(const Offset(220, 220), const Offset(300, 200));
      await tester.pumpAndSettle();
      expect(region, isNotNull);
      expect(region!.width, greaterThan(250));
      expect(region!.height, greaterThan(150));
      expect(moved, isFalse);
      expect(objects(d, 'instances').first['x'], 200);
    },
  );
}
