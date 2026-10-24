import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/foundation.dart';

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
}
