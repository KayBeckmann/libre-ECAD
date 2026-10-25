import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';
import '../bin/planning_sample.dart';

void main() {
  test(
    'PNG validation and macro planning references survive independent copies',
    () {
      final d = planningSample();
      final copied = insertMacro(insertMacro(emptyDrawing(), d), d);
      expect(copied['plans'], hasLength(2));
      expect(copied['calculations'], hasLength(4));
      for (final c in (copied['calculations'] as List).cast<Json>()) {
        expect(calculate(copied, c)['status'], 'estimate');
      }
      expect(validateDrawing(copied), copied);
      final routes = (copied['plans'] as List)
          .map((p) => p['routes'][0]['id'])
          .toSet();
      expect(routes, hasLength(2));
      copied['plans'][1]['routes'][0]['id'] =
          copied['plans'][0]['routes'][0]['id'];
      expect(() => validateDrawing(copied), throwsFormatException);
      final b = d['plans'][0]['background'];
      b['png'] = base64Encode(base64Decode(b['png']).take(24).toList());
      expect(() => validateDrawing(d), throwsFormatException);
    },
  );
  Json fixture() {
    final d = emptyDrawing(),
        sid = objects(emptyDrawing(), 'sheets').first['id'];
    d['sheets'] = [
      {'id': sid, 'number': 1, 'title': 'Installation'},
    ];
    final a = addSymbol(d, 'terminal', sid, 100, 100),
        b = addSymbol(d, 'switch', sid, 300, 100);
    d['plans'] = [
      {
        'id': sid,
        'kind': 'installation',
        'calibration': {
          'a': {'x': 100, 'y': 100},
          'b': {'x': 300, 'y': 100},
          'metres': 10,
          'source': 'Referenzplan TEST',
          'perspectiveConfirmed': true,
        },
        'circuits': [
          {
            'id': 'c',
            'name': 'Licht',
            'distribution': 'UV1',
            'deviceIds': [a['deviceId'], b['deviceId']],
          },
        ],
        'routes': [
          {
            'id': 'r',
            'name': 'Weg',
            'from': a['id'],
            'to': b['id'],
            'points': <Json>[],
            'circuitId': 'c',
            'allowanceM': 2,
          },
        ],
      },
    ];
    return d;
  }

  test(
    'route derives length from current positions and explicit scale, never stale cached length',
    () {
      final d = fixture(),
          p = (d['plans'] as List).first as Json,
          r = p['routes'][0] as Json;
      expect(validateDrawing(d), d);
      expect(routeLength(d, p, r)['metres'], 12);
      objects(d, 'instances')[1]['x'] = 500;
      expect(routeLength(d, p, r)['metres'], 22);
      p['calibration']['perspectiveConfirmed'] = false;
      expect(routeLength(d, p, r)['metres'], isNull);
      expect(
        drawingFindings(d).any((f) => f['id'].startsWith('scale:')),
        isTrue,
      );
      expect(
        canonicalJson(validateDrawing(jsonDecode(canonicalJson(d)))),
        canonicalJson(d),
      );
    },
  );
  test(
    'invalid calibration, dangling circuit and route references rejected',
    () {
      for (final edit in <void Function(Json)>[
        (d) => d['plans'][0]['calibration']['metres'] = 0,
        (d) => d['plans'][0]['calibration']['b'] = {'x': 100, 'y': 100},
        (d) => d['plans'][0]['routes'][0]['from'] = 'missing',
        (d) => d['plans'][0]['circuits'][0]['deviceIds'] = ['missing'],
        (d) => d['plans'][0]['routes'][0]['allowanceM'] = -1,
      ]) {
        final d = fixture();
        edit(d);
        expect(() => validateDrawing(d), throwsFormatException);
      }
    },
  );
  test(
    'article dimensions and physical devices shared by independent layout views',
    () {
      final d = fixture(), p = d['plans'][0] as Json;
      p['kind'] = 'layout';
      p['mmPerUnit'] = 2;
      // A layout uses its explicit millimetre scale, never a retained floor-plan calibration.
      expect(routeLength(d, p, p['routes'][0])['metres'], closeTo(2.4, 1e-10));
      p.remove('calibration');
      expect(routeLength(d, p, p['routes'][0])['metres'], closeTo(2.4, 1e-10));
      final dev = objects(d, 'devices').first;
      dev['article'] = articleSnapshot({
        'id': 'article',
        'version': 3,
        'articleNumber': 'TEST',
        'name': 'Gehäuse',
        'origin': 'Test',
        'license': 'CC0',
        'layers': {
          'mechanical': {'widthMm': 200, 'heightMm': 100},
          'thermal': {'powerLossW': 0},
        },
      });
      final r = layoutRectangle(d, p, objects(d, 'instances').first)!;
      expect(r['width'], 100);
      expect(r['height'], 50);
      expect(validateDrawing(d), d);
      expect(
        drawingFindings(d).any((f) => f['id'].startsWith('dimensions:')),
        isTrue,
      );
      final copy = cloneJson(d);
      copy['devices'][0]['article']['version'] = 4;
      expect(drawingChanges(d, copy).single['kind'], 'devices');
    },
  );
}
