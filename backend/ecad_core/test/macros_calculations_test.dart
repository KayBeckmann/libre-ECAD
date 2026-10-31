import 'dart:math' as math;
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'terminal strips survive macro extraction and get fresh identities on insert',
    () {
      final source = emptyDrawing();
      final sheet = objects(source, 'sheets').first['id'] as String;
      final first = addSymbol(source, 'terminal', sheet, 200, 200);
      final second = addSymbol(source, 'terminal', sheet, 400, 200);
      final strip = createTerminalStrip(source, 'X1');
      assignTerminalToStrip(source, first['deviceId'], strip['id'], '1');
      assignTerminalToStrip(source, second['deviceId'], strip['id'], 'PE');
      final region = extractMacroRegion(source, sheet, 100, 100, 500, 300);
      expect(objects(region, 'terminalStrips'), hasLength(1));
      expect(objects(region, 'devices').map((d) => d['terminalStripId']), [
        strip['id'],
        strip['id'],
      ]);
      final target = emptyDrawing();
      createTerminalStrip(target, 'X1');
      final inserted = insertMacro(target, region);
      final groups = objects(inserted, 'terminalStrips');
      expect(groups, hasLength(2));
      final copiedStrip = groups.singleWhere(
        (s) => s['id'] != objects(target, 'terminalStrips').single['id'],
      );
      expect(copiedStrip['bmk'], isNot('X1'));
      expect(objects(inserted, 'devices').map((d) => d['terminalStripId']), [
        copiedStrip['id'],
        copiedStrip['id'],
      ]);
      expect(
        objects(
          inserted,
          'devices',
        ).map((d) => (d['terminals'] as List).single['label']),
        containsAll(['1', 'PE']),
      );
      expect(validateDrawing(inserted), inserted);
    },
  );

  test(
    'both macro use cases clone all identities, contacts, continuations and cables without joining networks',
    () {
      for (final kind in ['distribution', 'motor', 'three-phase']) {
        final source = sampleDrawing(kind),
            target = emptyDrawing(),
            meta = {
              'id': 'macro',
              'version': 2,
              'name': 'Test',
              'origin': 'Own',
              'license': 'CC0-1.0',
            };
        final once = insertMacro(target, source, provenance: meta),
            twice = insertMacro(once, source, provenance: meta);
        expect(
          objects(twice, 'devices').length,
          objects(source, 'devices').length * 2,
        );
        expect(
          objects(twice, 'wires').length,
          objects(source, 'wires').length * 2,
        );
        expect(
          objects(twice, 'sheets').length,
          objects(source, 'sheets').length * 2 + 1,
        );
        for (final k in [
          'devices',
          'instances',
          'wires',
          'nodes',
          'continuations',
          'cables',
        ]) {
          final ids = objects(source, k).map((o) => o['id']).toSet();
          expect(objects(twice, k).any((o) => ids.contains(o['id'])), isFalse);
        }
        expect(nets(twice).length, nets(source).length * 2);
        expect(twice['macroSources'], hasLength(2));
        expect(validateDrawing(twice), twice);
        expect(objects(target, 'devices'), isEmpty);
      }
    },
  );
  test(
    'macro insertion remaps custom symbol types and leaves source article immutable',
    () {
      final d = emptyDrawing();
      d['symbols'] = [symbolTemplate('switch', 'test')];
      addSymbol(d, 'custom_test', objects(d, 'sheets').first['id'], 200, 200);
      final copy = insertMacro(emptyDrawing(), d);
      expect(objects(copy, 'devices').first['type'], isNot('custom_test'));
      expect(validateDrawing(copy), copy);
      expect(objects(d, 'devices').first['type'], 'custom_test');
    },
  );
  Json voltage() => {
    'id': 'calc',
    'name': 'Voltage TEST',
    'kind': 'voltage',
    'source': 'Manufacturer R/X reference TEST',
    'conditions': 'balanced inductive load, stated operating temperature',
    'phase': 'balanced3',
    'inputs': <String, dynamic>{
      'currentA': 10,
      'voltageV': 400,
      'lengthM': 100,
      'areaMm2': 2.5,
      'resistanceOhmPerKm': 8,
      'reactanceOhmPerKm': 0.1,
      'cosPhi': 0.8,
      'limitPercent': 3,
      'ampacityA': 20,
      'breakerA': 16,
    },
  };
  test(
    'voltage formula, explicit source and input plausibility, missing data never becomes zero',
    () {
      final d = emptyDrawing(), c = voltage(), result = calculate(d, c);
      expect(result['status'], 'estimate');
      expect(
        result['results']['dropV'],
        closeTo(math.sqrt(3) * 10 * 0.1 * (8 * 0.8 + 0.1 * 0.6), 1e-10),
      );
      final minimum = result['results']['minimumAreaVoltageMm2'] as num;
      expect(minimum, greaterThan(0));
      c['inputs']['resistanceOhmPerKm'] = 8 * 2.5 / minimum;
      expect(calculate(d, c)['results']['dropPercent'], closeTo(3, 1e-10));
      c['inputs']['resistanceOhmPerKm'] = 8;
      c['phase'] = 'single';
      expect(calculate(d, c)['results']['dropV'], closeTo(12.92, 1e-10));
      c['inputs']['cosPhi'] = 1.1;
      expect(calculate(d, c)['status'], 'incomplete');
      c['inputs']['cosPhi'] = 0.8;
      c['source'] = '';
      expect(calculate(d, c)['results'], isEmpty);
      c['source'] = 'test';
      c['inputs']['ampacityA'] = null;
      expect(calculate(d, c)['results'], isEmpty);
    },
  );
  test(
    'thermal estimate counts each physical device once and missing thermal data blocks result',
    () {
      final d = sampleDrawing('motor'), dev = objects(d, 'devices').first;
      dev['article'] = articleSnapshot({
        'id': 'a',
        'version': 1,
        'articleNumber': 'TEST',
        'name': 'Test',
        'origin': 'own',
        'license': 'CC0',
        'layers': {
          'thermal': {'powerLossW': 100, 'conditions': 'TEST full load'},
        },
      });
      final c = <String, dynamic>{
        'id': 'heat',
        'name': 'Thermal',
        'kind': 'thermal',
        'source': 'TEST surface and coefficient',
        'conditions': 'stationary test',
        'deviceIds': [dev['id']],
        'inputs': <String, dynamic>{
          'ambientC': 25,
          'insideC': 35,
          'areaM2': 1,
          'coefficient': 5,
        },
      };
      expect(calculate(d, c)['results']['requiredCoolingW'], 50);
      c['inputs']['ambientC'] = 40;
      expect(calculate(d, c)['results']['requiredCoolingW'], 125);
      dev['article']['powerLossW'] = 0;
      expect(calculate(d, c)['status'], 'estimate');
      dev['article']['thermalConditions'] = '';
      expect(calculate(d, c)['results'], isEmpty);
    },
  );
}
