import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
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
      final duplicate = cloneJson(d);
      objects(duplicate, 'devices')[1]['bmk'] = objects(
        duplicate,
        'devices',
      )[0]['bmk'];
      expect(drawingFindings(duplicate).single['severity'], 'error');
      expect(drawingChanges(d, changed).single['kind'], 'wires');
    },
  );
}
