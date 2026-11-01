import 'dart:convert';
import 'dart:math';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test('wire caption stays adjacent to a real route segment', () {
    expect(
      wireLabelPosition([const Point(100, 200), const Point(400, 200)]),
      const Point(108.0, 195.0),
    );
    expect(
      wireLabelPosition([const Point(100, 100), const Point(100, 400)]),
      const Point(106.0, 250.0),
    );
    expect(
      wireLabelPosition([
        const Point(100, 100),
        const Point(100, 120),
        const Point(400, 120),
      ]),
      const Point(108.0, 115.0),
    );
  });
  test('both working examples preserve references through serialization', () {
    for (final kind in ['distribution', 'motor']) {
      final d = sampleDrawing(kind);
      expect(objects(d, 'sheets'), hasLength(2));
      expect(
        canonicalJson(validateDrawing(jsonDecode(canonicalJson(d)))),
        canonicalJson(d),
      );
      final relay = objects(
        d,
        'devices',
      ).firstWhere((o) => o['type'] == 'relay');
      expect(crossReferences(d, relay['id']), hasLength(2));
      relay['bmk'] = 'K-renamed';
      for (final i in objects(
        d,
        'instances',
      ).where((i) => i['deviceId'] == relay['id'])) {
        expect(objectById(d, 'devices', i['deviceId'])['bmk'], 'K-renamed');
      }
      expect(validateDrawing(d), isNotNull);
    }
  });
  test(
    'BMK allocation begins without suffix then .1 and .2; move preserves identity',
    () {
      final d = emptyDrawing(), sheet = objects(emptyDrawing(), 'sheets').first;
      d['sheets'] = [sheet];
      final id = sheet['id'] as String;
      for (var i = 0; i < 3; i++) {
        addSymbol(d, 'breaker', id, 400, 100 + i * 100);
      }
      expect(objects(d, 'devices').map((o) => o['bmk']), [
        '1-Q4',
        '1-Q4.1',
        '1-Q4.2',
      ]);
      final view = objects(d, 'instances').first;
      final before = objectById(d, 'devices', view['deviceId'])['bmk'];
      view['x'] = 800;
      expect(objectById(d, 'devices', view['deviceId'])['bmk'], before);
      expect(positionReference(d, view), '1/A7');
      objects(d, 'devices')[1]['bmk'] = before;
      expect(() => validateDrawing(d), throwsFormatException);
    },
  );
  test(
    'crossing geometry stays separate; explicit junction joins, removing wire splits',
    () {
      final d = emptyDrawing(), sheet = objects(emptyDrawing(), 'sheets').first;
      d['sheets'] = [sheet];
      final sid = sheet['id'];
      d['nodes'] = [
        {'id': 'left', 'sheetId': sid, 'x': 200, 'y': 300},
        {'id': 'right', 'sheetId': sid, 'x': 600, 'y': 300},
        {'id': 'top', 'sheetId': sid, 'x': 400, 'y': 100},
        {'id': 'bottom', 'sheetId': sid, 'x': 400, 'y': 500},
      ];
      Json wire(String id, String from, String to) => {
        'id': id,
        'sheetId': sid,
        'from': pointRef('node', from),
        'to': pointRef('node', to),
      };
      d['wires'] = [
        wire('horizontal', 'left', 'right'),
        wire('vertical', 'top', 'bottom'),
      ];
      expect(nets(validateDrawing(d)), hasLength(2));
      (d['nodes'] as List).add({
        'id': 'junction',
        'sheetId': sid,
        'x': 400,
        'y': 300,
      });
      d['wires'] = [
        wire('a', 'left', 'junction'),
        wire('b', 'junction', 'right'),
        wire('c', 'top', 'junction'),
        wire('d', 'junction', 'bottom'),
      ];
      expect(nets(validateDrawing(d)), hasLength(1));
      (d['wires'] as List).removeLast();
      expect(nets(validateDrawing(d)), hasLength(2));
    },
  );
  test(
    'same terminal in two views is one endpoint, contact and coil remain distinct',
    () {
      final d = emptyDrawing();
      final sid = objects(d, 'sheets').first['id'];
      final coil = addSymbol(d, 'coil', sid, 200, 200);
      final copy = addSymbol(
        d,
        'coil',
        sid,
        600,
        200,
        deviceId: coil['deviceId'],
      );
      final contact = addSymbol(
        d,
        'contact',
        sid,
        800,
        200,
        deviceId: coil['deviceId'],
      );
      expect(
        endpointKey(d, portRef(coil['id'], 'A1')),
        endpointKey(d, portRef(copy['id'], 'A1')),
      );
      expect(
        endpointKey(d, portRef(coil['id'], 'A1')),
        isNot(endpointKey(d, portRef(contact['id'], '13'))),
      );
      expect(nets(validateDrawing(d)), hasLength(4));
    },
  );
  test('cross-sheet references follow a later free-text net potential', () {
    final d = sampleDrawing('motor');
    final ends = objects(d, 'continuations');
    final first = ends[0], second = ends[1];
    final source = objects(
      d,
      'wires',
    ).singleWhere((w) => w['to']['id'] == first['id']);
    final target = objects(
      d,
      'wires',
    ).singleWhere((w) => w['from']['id'] == second['id']);
    expect(
      continuationCaption(d, first),
      'Nach ${positionReference(d, second)}',
    );
    expect(
      continuationCaption(d, second),
      'Von ${positionReference(d, first)}',
    );
    setNetPotential(d, source['id'], '+24V Steuerung');
    expect(wirePotential(d, source), '+24V Steuerung');
    expect(wirePotential(d, target), '+24V Steuerung');
    expect(
      continuationCaption(d, first),
      'Nach ${positionReference(d, second)} · +24V Steuerung',
    );
    expect(
      continuationCaption(d, second),
      'Von ${positionReference(d, first)} · +24V Steuerung',
    );
    expect(validateDrawing(d), isNotNull);
    setNetPotential(d, target['id'], '0V Steuerung');
    expect(wirePotential(d, source), '0V Steuerung');
    setNetPotential(d, source['id'], '');
    expect(wirePotential(d, target), isNull);
    expect(
      continuationCaption(d, second),
      'Von ${positionReference(d, first)}',
    );
  });
  test('potential names reject control text and conflicting net snapshots', () {
    final d = sampleDrawing('motor');
    final ends = objects(d, 'continuations');
    final a = objects(
      d,
      'wires',
    ).singleWhere((w) => w['to']['id'] == ends.first['id']);
    final b = objects(
      d,
      'wires',
    ).singleWhere((w) => w['from']['id'] == ends.last['id']);
    expect(() => setNetPotential(d, a['id'], 'A\nB'), throwsFormatException);
    setNetPotential(d, a['id'], 'Steuerkreis Nord');
    expect(wirePotential(validateDrawing(d), b), 'Steuerkreis Nord');
    b['potential'] = 'Steuerkreis Süd';
    expect(() => validateDrawing(d), throwsFormatException);
  });
  test('new cross-page link directions are validated and reversible', () {
    final d = sampleDrawing('motor');
    final pair = objects(d, 'continuations');
    pair[0]['direction'] = 'in';
    pair[1]['direction'] = 'out';
    expect(continuationCaption(d, pair[0]), startsWith('Von '));
    expect(continuationCaption(d, pair[1]), startsWith('Nach '));
    expect(validateDrawing(d), isNotNull);
    pair[1]['direction'] = 'in';
    expect(() => validateDrawing(d), throwsFormatException);
  });
  test('continuations join by stable link ID, not equal labels', () {
    final d = sampleDrawing('motor');
    final continuations = objects(d, 'continuations');
    expect(
      endpointKey(d, pointRef('continuation', continuations[0]['id'])),
      endpointKey(d, pointRef('continuation', continuations[1]['id'])),
    );
    continuations[1]['linkId'] = 'unrelated';
    expect(() => validateDrawing(d), throwsFormatException);
  });
  test(
    'malformed references, coordinates, duplicate core and unknown fields rejected',
    () {
      final good = sampleDrawing('motor');
      for (final mutate in <void Function(Json)>[
        (d) => objects(d, 'instances').first['deviceId'] = 'missing',
        (d) => objects(d, 'instances').first['x'] = 12,
        (d) => objects(d, 'instances').first['y'] = double.nan,
        (d) => objects(d, 'wires').first['from'] = {
          'kind': 'port',
          'instanceId': 'missing',
          'terminalId': '1',
        },
        (d) => objects(d, 'sheets')[1]['number'] = 1,
        (d) => d['secret'] = 'reject unknown metadata',
        (d) {
          final wired = objects(
            d,
            'wires',
          ).firstWhere((w) => w['cableId'] != null);
          objects(d, 'wires').first.addAll({
            'cableId': wired['cableId'],
            'coreId': wired['coreId'],
          });
        },
      ]) {
        final d = cloneJson(good);
        mutate(d);
        expect(() => validateDrawing(d), throwsFormatException);
      }
    },
  );
  test('canonical serialization is stable under object and key reordering', () {
    final d = sampleDrawing('distribution'), copy = sampleDrawing('motor');
    copy.clear();
    copy.addAll(cloneJson(d));
    copy['devices'] = (copy['devices'] as List).reversed.toList();
    expect(canonicalJson(copy), canonicalJson(d));
  });
}
