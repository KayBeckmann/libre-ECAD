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
