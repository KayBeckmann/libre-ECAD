import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/drawing/drawing_canvas.dart';
import 'package:libre_ecad_app/src/drawing/drawing_controller.dart';

void main() {
  test('rotation advances by quarter turns and carries electrical pins', () {
    final d = emptyDrawing(), sheet = objects(d, 'sheets').first['id'];
    final instance = addSymbol(d, 'coil', sheet, 400, 300);
    final pin = instancePorts(d, instance).first;
    final original = endpointPosition(d, portRef(instance['id'], pin));
    final c = DrawingController(d);
    c.rotateInstance(instance['id']);
    final rotated = objectById(c.drawing, 'instances', instance['id']);
    expect(rotated['rotation'], 90);
    final p = endpointPosition(c.drawing, portRef(instance['id'], pin));
    expect(p.x, 400 - (original.y - 300));
    expect(p.y, 300 + (original.x - 400));
    for (var n = 0; n < 3; n++) { c.rotateInstance(instance['id']); }
    expect(objectById(c.drawing, 'instances', instance['id'])['rotation'], 0);
    c.dispose();
  });

  test('moving a wire bend retains both endpoints and electrical identity', () {
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    (d['nodes'] as List).addAll(<Json>[
      {'id': 'a', 'sheetId': sid, 'x': 200, 'y': 200},
      {'id': 'b', 'sheetId': sid, 'x': 600, 'y': 400},
    ]);
    (d['wires'] as List).add({'id': 'w', 'sheetId': sid,
      'from': pointRef('node', 'a'), 'to': pointRef('node', 'b')});
    final c = DrawingController(d);
    final before = nets(c.drawing).length;
    c.moveWireSegment('w', 1, const Offset(320, 340));
    final wire = objectById(c.drawing, 'wires', 'w');
    final route = wireRoute(c.drawing, wire);
    expect(route.first, const Offset(200, 200));
    expect(route.last, const Offset(600, 400));
    expect(route, [const Offset(200, 200), const Offset(320, 200),
      const Offset(320, 400), const Offset(600, 400)]);
    expect(nets(c.drawing).length, before);
    c.undo();
    expect(objectById(c.drawing, 'wires', 'w')['waypoints'], isNull);
    c.dispose();
  });

  test('automatic route detours around an unrelated symbol body', () {
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    addSymbol(d, 'coil', sid, 400, 300);
    (d['nodes'] as List).addAll(<Json>[
      {'id': 'a', 'sheetId': sid, 'x': 200, 'y': 300},
      {'id': 'b', 'sheetId': sid, 'x': 600, 'y': 300},
    ]);
    final wire = {'id': 'w', 'sheetId': sid,
      'from': pointRef('node', 'a'), 'to': pointRef('node', 'b')};
    final route = wireRoute(d, wire);
    expect(route.first, const Offset(200, 300));
    expect(route.last, const Offset(600, 300));
    expect(route.any((p) => p.dy != 300), isTrue);
    for (var n = 0; n < route.length - 1; n++) {
      final a = route[n], b = route[n + 1];
      expect((a.dx == b.dx && a.dx > 352 && a.dx < 448 &&
          a.dy <= 324 && b.dy >= 276) ||
          (a.dy == b.dy && a.dy > 276 && a.dy < 324 &&
          a.dx <= 448 && b.dx >= 352), isFalse);
    }
  });

  test('route escapes a blocked endpoint column before detouring', () {
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    for (final p in [const Offset(200, 260), const Offset(200, 340), const Offset(400, 300)]) {
      addSymbol(d, 'coil', sid, p.dx, p.dy);
    }
    (d['nodes'] as List).addAll(<Json>[
      {'id': 'a', 'sheetId': sid, 'x': 200, 'y': 300},
      {'id': 'b', 'sheetId': sid, 'x': 600, 'y': 300},
    ]);
    final wire = {'id': 'blocked', 'sheetId': sid,
      'from': pointRef('node', 'a'), 'to': pointRef('node', 'b')};
    final route = wireRoute(d, wire);
    expect(route.first, const Offset(200, 300));
    expect(route.last, const Offset(600, 300));
    for (var n = 0; n < route.length - 1; n++) {
      final a = route[n], b = route[n + 1];
      expect(a.dx == b.dx || a.dy == b.dy, isTrue);
      for (final obstacle in [const Offset(200, 260), const Offset(200, 340), const Offset(400, 300)]) {
        final r = Rect.fromCenter(center: obstacle, width: 96, height: 48);
        final crosses = a.dx == b.dx
          ? a.dx > r.left && a.dx < r.right &&
            (a.dy < b.dy ? b.dy : a.dy) > r.top &&
            (a.dy > b.dy ? b.dy : a.dy) < r.bottom
          : a.dy > r.top && a.dy < r.bottom &&
            (a.dx < b.dx ? b.dx : a.dx) > r.left &&
            (a.dx > b.dx ? b.dx : a.dx) < r.right;
        expect(crosses, isFalse, reason: 'Segment $a → $b crosses $r');
      }
    }
  });

  test('dragging a middle segment shifts its whole lane without diagonal breaks', () {
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    (d['nodes'] as List).addAll(<Json>[
      {'id': 'a', 'sheetId': sid, 'x': 100, 'y': 100},
      {'id': 'b', 'sheetId': sid, 'x': 500, 'y': 300},
    ]);
    (d['wires'] as List).add({'id': 'w', 'sheetId': sid,
      'from': pointRef('node', 'a'), 'to': pointRef('node', 'b'),
      'waypoints': [{'x': 100, 'y': 200}, {'x': 500, 'y': 200}]});
    final c = DrawingController(d);
    c.moveWireSegment('w', 1, const Offset(300, 260));
    final route = wireRoute(c.drawing, objectById(c.drawing, 'wires', 'w'));
    expect(route, [const Offset(100, 100), const Offset(100, 260),
      const Offset(500, 260), const Offset(500, 300)]);
    expect(nets(c.drawing).length, nets(d).length);
    c.dispose();
  });

  testWidgets('pan mode drags the canvas even when starting over a symbol', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    addSymbol(d, 'coil', sid, 200, 200);
    var moved = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawingCanvas(
      drawing: d, sheetId: sid, projectName: 'Pan', version: 1,
      selected: null, editable: false, panning: true,
      onTap: (_) {}, onSelect: (_) {}, onMove: (_, _) => moved = true,
      onPort: (_) {},
    ))));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final before = viewer.transformationController!.value.clone();
    await tester.dragFrom(const Offset(220, 220), const Offset(130, 90));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value, isNot(before));
    expect(moved, isFalse);
  });

  testWidgets('dragging a wire handle reroutes it without changing endpoints', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
    (d['nodes'] as List).addAll(<Json>[
      {'id': 'a', 'sheetId': sid, 'x': 200, 'y': 200},
      {'id': 'b', 'sheetId': sid, 'x': 600, 'y': 400},
    ]);
    (d['wires'] as List).add({'id': 'w', 'sheetId': sid,
      'from': pointRef('node', 'a'), 'to': pointRef('node', 'b')});
    final c = DrawingController(d);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawingCanvas(
      drawing: c.drawing, sheetId: sid, projectName: 'Wire', version: 1,
      selected: null, editable: true,
      onTap: (_) {}, onSelect: (_) {}, onMove: (_, _) {}, onPort: (_) {},
      onWireSegment: c.moveWireSegment,
    ))));
    await tester.pumpAndSettle();
    final handle = find.bySemanticsIdentifier('ecad-hit-wire-w-1');
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(0, 80));
    await tester.pumpAndSettle();
    final points = wireRoute(c.drawing, objectById(c.drawing, 'wires', 'w'));
    expect(points.first, const Offset(200, 200));
    expect(points.last, const Offset(600, 400));
    expect(objectById(c.drawing, 'wires', 'w')['waypoints'], isNotNull);
    c.dispose();
  });
}
