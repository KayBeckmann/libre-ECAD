import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test('PXL-compatible 1-pole circuit glyph has thermal and magnetic marks', () {
    final symbol = symbolByKey('mcb1');
    final shapes = symbolGeometry(symbol);
    bool stroke(num x, num y, num x2, num y2) => shapes.any((s) =>
      s['kind'] == 'line' && s['x'] == x && s['y'] == y &&
      s['x2'] == x2 && s['y2'] == y2);
    expect(symbolPins(symbol).map((p) => p['id']), ['1', '2']);
    expect(stroke(-10, -29, 0, 20), true); // slanted open moving contact
    expect(stroke(-25, -15, -25, -10), true); // bimetal zigzag
    expect(stroke(-28, 5, -20, 0), true); // magnetic arrowhead
    expect(shapes.any((s) => s['kind'] == 'text' && s['text'] == 'I>'), false);
  });
  test('catalog article names the existing symbol and material row', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first['id'] as String;
    final instance = addSymbol(d, 'mcb1', sheet, 200, 200);
    final dev = objectById(d, 'devices', instance['deviceId']);
    dev['article'] = articleSnapshot({
      'id': 'catalog-fiktiv-demo', 'version': 1,
      'articleNumber': 'DEMO-236', 'name': 'TEST-B16/1',
      'manufacturerName': 'FIKTIV', 'license': 'Ungeklärt',
      'origin': 'Testkatalog Seite 1',
    });
    expect(deviceDisplayLabel(dev), 'TEST-B16/1');
    final row = (documentData({'id': 'p', 'name': 'Test', 'version': 1,
      'drawing': d})['material'] as List).single;
    expect(row['label'], 'TEST-B16/1');
    expect(row['articleNumber'], 'DEMO-236');
    expect(row['typeName'], 'Leitungsschutzschalter 1-polig');
    expect(row['type'], 'mcb1'); // machine-readable key stays unchanged
  });
  test('lists count shared relay once and retain connections', () {
    final d = sampleDrawing('motor');
    final data = documentData({
      'id': 'p',
      'name': 'Motor',
      'version': 8,
      'drawing': d,
    });
    expect(
      (data['material'] as List).where((m) => m['type'] == 'relay').length,
      1,
    );
    expect((data['connections'] as List).length, objects(d, 'wires').length);
    expect(data['version'], 8);
    expect(
      (data['cables'] as List).length,
      objects(
        d,
        'cables',
      ).fold<int>(0, (sum, c) => sum + (c['cores'] as List).length),
    );
  });
  test(
    'open/occupied contacts link to objects; invalid references and duplicates block',
    () {
      final d = emptyDrawing(),
          sheet = objects(emptyDrawing(), 'sheets').first['id'];
      objects(d, 'sheets').first['id'] = sheet;
      final a = addSymbol(d, 'switch', sheet, 200, 200),
          b = addSymbol(d, 'terminal', sheet, 200, 400),
          c = addSymbol(d, 'terminal', sheet, 400, 400);
      expect(
        drawingFindings(
          d,
        ).any((f) => f['objectId'] == a['id'] && f['id'].startsWith('open:')),
        true,
      );
      (d['wires'] as List).addAll(<Json>[
        {
          'id': 'w1',
          'sheetId': sheet,
          'from': portRef(a['id'], '1'),
          'to': portRef(b['id'], '1'),
        },
        {
          'id': 'w2',
          'sheetId': sheet,
          'from': portRef(a['id'], '1'),
          'to': portRef(c['id'], '1'),
        },
      ]);
      expect(
        drawingFindings(d).any((f) => f['id'].startsWith('occupied:')),
        true,
      );
      final changed = cloneJson(d);
      (changed['wires'] as List).first['to'] = portRef('missing', '1');
      expect(drawingFindings(changed).single['severity'], 'error');
      expect(drawingFindings(changed).single['objectId'], 'w1');
      final duplicate = cloneJson(d);
      objects(duplicate, 'devices')[1]['bmk'] = objects(
        duplicate,
        'devices',
      )[0]['bmk'];
      expect(drawingFindings(duplicate).single['severity'], 'error');
      expect(drawingFindings(duplicate).single['objectId'], b['id']);
      expect(drawingChanges(d, changed).single['kind'], 'wires');
    },
  );
}
