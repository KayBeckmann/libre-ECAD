import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

import 'drawing_canvas.dart';

class DrawingController extends ChangeNotifier {
  DrawingController(Json initial) : drawing = validateDrawing(initial);
  Json drawing;
  final List<Json> _undo = [], _redo = [];
  String? saved;
  bool get dirty => canonicalJson(drawing) != saved;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void markSaved() {
    saved = canonicalJson(drawing);
    notifyListeners();
  }

  void change(void Function(Json) edit) {
    final next = cloneJson(drawing);
    edit(next);
    final valid = validateDrawing(next);
    if (canonicalJson(valid) == canonicalJson(drawing)) return;
    _undo.add(drawing);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    drawing = valid;
    notifyListeners();
  }

  void replace(Json next) => change((d) {
    d.clear();
    d.addAll(next);
  });
  void undo() {
    if (!canUndo) return;
    _redo.add(drawing);
    drawing = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(drawing);
    drawing = _redo.removeLast();
    notifyListeners();
  }

  void removeInstance(String id) => change((d) {
    final i = objectById(d, 'instances', id);
    (d['wires'] as List).removeWhere(
      (w) => w['from']['instanceId'] == id || w['to']['instanceId'] == id,
    );
    (d['instances'] as List).removeWhere((v) => v['id'] == id);
    if (!objects(d, 'instances').any((v) => v['deviceId'] == i['deviceId'])) {
      (d['devices'] as List).removeWhere((v) => v['id'] == i['deviceId']);
    }
  });

  void rotateInstance(String id) => change((d) {
    final instance = objectById(d, 'instances', id);
    instance['rotation'] = ((instance['rotation'] as int? ?? 0) + 90) % 360;
  });

  void moveWireSegment(String id, int segment, Offset point) => change((d) {
    final wire = objectById(d, 'wires', id);
    final route = wireRoute(d, wire).toList();
    if (segment < 0 || segment >= route.length - 1) return;
    final a = route[segment], b = route[segment + 1];
    final horizontal = a.dy == b.dy;
    if (!horizontal && a.dx != b.dx) return;
    final x = ((point.dx / 20).round() * 20).clamp(0, 1200).toDouble();
    final y = ((point.dy / 20).round() * 20).clamp(0, 800).toDouble();
    Offset shifted(Offset p) => horizontal ? Offset(p.dx, y) : Offset(x, p.dy);
    if (route.length == 2) {
      route.insertAll(1, [shifted(a), shifted(b)]);
    } else if (segment == 0) {
      route[1] = shifted(b);
      route.insert(1, shifted(a));
    } else if (segment == route.length - 2) {
      route[segment] = shifted(a);
      route.insert(route.length - 1, shifted(b));
    } else {
      route[segment] = shifted(a);
      route[segment + 1] = shifted(b);
    }
    wire['waypoints'] = [
      for (final p in route.skip(1).take(route.length - 2))
        {'x': p.dx, 'y': p.dy},
    ];
  });
}
