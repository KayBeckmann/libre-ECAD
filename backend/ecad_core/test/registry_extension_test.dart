import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  const expected = <String, List<String>>{
    'mcb1': ['1', '2'],
    'mcb2': ['1', '3', '2', '4'],
    'mcb3': ['1', '3', '5', '2', '4', '6'],
    'rcd2': ['1', '3', '2', '4'],
    'rcd4': ['1', '3', '5', '7', '2', '4', '6', '8'],
    'rcbo2': ['1', '3', '2', '4'],
    'rcbo4': ['1', '3', '5', '7', '2', '4', '6', '8'],
    'motor_protection': ['1', '3', '5', '2', '4', '6'],
    'motor_dc': ['P', 'N'],
    'motor_1ph': ['L', 'N', 'PE'],
    'motor_6terminal': ['U1', 'V1', 'W1', 'U2', 'V2', 'W2'],
    'converter_ac_ac': ['L', 'N', 'OUT_L', 'OUT_N'],
    'converter_ac_dc': ['L', 'N', 'P', 'M'],
    'psu_pe': ['L', 'N', 'PE', 'P', 'M'],
    'heater': ['1', '2'],
    'potentiometer': ['1', '2', 'W'],
    'ldr': ['1', '2'],
    'transistor_npn': ['C', 'B', 'E'],
    'transistor_pnp': ['C', 'B', 'E'],
    'triac': ['MT1', 'MT2', 'G'],
    'diac': ['A1', 'A2'],
    'ic4': ['1', '2', '3', '4'],
    'ic6': ['1', '2', '3', '4', '5', '6'],
    'ic8': ['1', '2', '3', '4', '5', '6', '7', '8'],
    'ic10': ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
    'pcb_terminal2': ['1', '2'],
  };

  test(
    'each missing general symbol has unique electrical pins and valid vector',
    () {
      for (final e in expected.entries) {
        final s = symbolByKey(e.key);
        expect(s.ports, e.value, reason: e.key);
        expect(s.allPorts, e.value);
        final pins = symbolPins(s);
        expect(pins.map((p) => p['id']).toList(), e.value);
        expect({
          for (final p in pins) '${p['x']}/${p['y']}',
        }, hasLength(pins.length));
        final geometry = symbolGeometry(s);
        expect(geometry, isNotEmpty);
        for (final pin in pins) {
          expect(
            geometry.any(
              (shape) =>
                  shape['x'] == pin['x'] && shape['y'] == pin['y'] ||
                  shape['x2'] == pin['x'] && shape['y2'] == pin['y'],
            ),
            isTrue,
            reason: '${e.key}:${pin['id']} lacks a visible lead',
          );
        }
        expect(validateSymbol(symbolTemplate(e.key, 'probe')), isNotNull);
      }
      expect(
        symbolLibrary.map((s) => s.key).toSet(),
        hasLength(symbolLibrary.length),
      );
      expect(symbolLibrary.where((s) => s.group == 'Schutzgeräte'), isNotEmpty);
      expect(
        symbolLibrary.where((s) => s.group == 'Antriebe / Energie'),
        isNotEmpty,
      );
      expect(symbolLibrary.where((s) => s.group == 'Elektronik'), isNotEmpty);
      expect(
        symbolLibrary.where((s) => s.group == 'Anschlussklemmen'),
        isNotEmpty,
      );
    },
  );

  test('new symbols survive drawing serialization with separate terminals', () {
    final d = emptyDrawing();
    final sid = objects(d, 'sheets').first['id'] as String;
    for (final e in expected.entries) {
      final i = addSymbol(d, e.key, sid, 400, 400);
      expect(instancePorts(d, i), e.value);
      for (final pin in e.value) {
        expect(endpointPosition(d, portRef(i['id'], pin)), isNotNull);
      }
    }
    expect(validateDrawing(jsonDecode(canonicalJson(d))), isNotNull);
  });

  test(
    'protective contacts show an open blade and isolated upper terminal',
    () {
      for (final key in [
        'mcb1',
        'mcb2',
        'mcb3',
        'rcd2',
        'rcd4',
        'rcbo2',
        'rcbo4',
      ]) {
        final source = symbolByKey(key);
        final pins = symbolPins(source);
        final columns = pins.length ~/ 2;
        for (final shapes in [
          symbolGeometry(source),
          (symbolTemplate(key, 'probe')['primitives'] as List)
              .cast<Map<String, dynamic>>(),
        ]) {
          expect(
            shapes.where((s) => s['kind'] == 'rect'),
            isEmpty,
            reason: key,
          );
          final circles = shapes.where((s) => s['kind'] == 'circle').toList();
          expect(circles, hasLength(columns * 2), reason: key);
          expect(
            circles.every((s) => (s['radius'] as num) <= 5),
            isTrue,
            reason: key,
          );
          bool joins(num x, num y, num x2, num y2) => shapes.any(
            (s) =>
                s['kind'] == 'line' &&
                ((s['x'] == x &&
                        s['y'] == y &&
                        s['x2'] == x2 &&
                        s['y2'] == y2) ||
                    (s['x'] == x2 &&
                        s['y'] == y2 &&
                        s['x2'] == x &&
                        s['y2'] == y)),
          );
          // Mechanical coupling sits between contact columns, not on a stem.
          for (var i = 0; i < columns - 1; i++) {
            final x = pins[i]['x'] as num;
            expect(
              joins(x + 20, 10, x + 30, 10),
              isTrue,
              reason: '$key mechanical coupling $i',
            );
          }
          for (var i = 0; i < columns; i++) {
            final x = pins[i]['x'] as num;
            expect(joins(x, -60, x, -20), isTrue, reason: '$key upper lead $i');
            expect(joins(x, 20, x, 60), isTrue, reason: '$key lower lead $i');
            expect(
              joins(x, 20, x + 20, -10),
              isTrue,
              reason: '$key open blade $i',
            );
            expect(
              shapes.where(
                (s) =>
                    s['kind'] == 'line' &&
                    ((s['x'] == x && s['y'] == -20 && s['y2'] != -60) ||
                        (s['x2'] == x && s['y2'] == -20 && s['y'] != -60)),
              ),
              isEmpty,
              reason: '$key upper terminal must not touch the blade',
            );
          }
        }
      }
    },
  );

  test('relay NO gap contrasts with the continuous resting NC path', () {
    for (final key in ['contact', 'contact_nc']) {
      final pins = symbolPins(symbolByKey(key));
      expect(pins.map((p) => [p['x'], p['y']]).toList(), [
        [0, -40],
        [0, 40],
      ]);
      for (final shapes in [
        symbolGeometry(symbolByKey(key)),
        (symbolTemplate(key, 'probe')['primitives'] as List)
            .cast<Map<String, dynamic>>(),
      ]) {
        bool joins(num x, num y, num x2, num y2) => shapes.any(
          (s) =>
              s['kind'] == 'line' &&
              ((s['x'] == x && s['y'] == y && s['x2'] == x2 && s['y2'] == y2) ||
                  (s['x2'] == x &&
                      s['y2'] == y &&
                      s['x'] == x2 &&
                      s['y'] == y2)),
        );
        expect(joins(0, -40, 0, -20), isTrue, reason: '$key upper lead');
        expect(joins(0, 20, 0, 40), isTrue, reason: '$key lower lead');
        if (key == 'contact') {
          expect(joins(0, 20, 20, -10), isTrue, reason: 'NO movable blade');
          expect(
            joins(0, 20, 0, -20),
            isFalse,
            reason: 'NO must not short the gap',
          );
        } else {
          expect(
            joins(0, 20, 0, -20),
            isTrue,
            reason: 'NC blade touches fixed upper terminal',
          );
        }
      }
    }
  });

  test(
    'previous pinned revision remains readable but altered pin sets do not',
    () {
      final old = cloneJson(pinnedLibrary());
      old['version'] = 'libre-ecad-synthetic-4';
      const previous = {
        'supply',
        'breaker',
        'terminal',
        'switch',
        'coil',
        'contact',
        'motor',
        'contact_nc',
        'supply3',
        'breaker3',
        'plc',
        'drive',
        'safety',
        'earth',
        'fuse',
        'resistor',
        'capacitor',
        'diode',
        'led',
        'battery',
        'transformer',
        'lamp',
        'push_no',
        'push_nc',
        'changeover',
        'buzzer',
        'voltmeter',
        'ammeter',
        'solar_cell',
      };
      old['symbols'] = (old['symbols'] as List)
          .where((s) => previous.contains(s['id']))
          .toList();
      expect(supportsLibrary(old), isTrue);
      old['symbols'][0]['ports'] = ['invalid'];
      expect(supportsLibrary(old), isFalse);
    },
  );
}
