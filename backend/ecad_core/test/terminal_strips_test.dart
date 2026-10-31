import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  Json project(Json drawing) => {
    'id': 'p',
    'name': 'Terminal test',
    'version': 1,
    'drawing': drawing,
  };

  test(
    'strip assignment keeps device and electrical endpoint IDs while displaying X1:1',
    () {
      final d = emptyDrawing(),
          sheet = objects(d, 'sheets').first['id'] as String;
      final a = addSymbol(d, 'terminal', sheet, 200, 200);
      final b = addSymbol(d, 'terminal', sheet, 400, 200);
      final aDevice = objectById(d, 'devices', a['deviceId']);
      final oldKey = endpointKey(d, portRef(a['id'], '1'));
      final oldBmk = aDevice['bmk'];
      final strip = createTerminalStrip(d, 'X1');
      assignTerminalToStrip(d, a['deviceId'], strip['id'], '1');
      assignTerminalToStrip(d, b['deviceId'], strip['id'], 'N');
      expect(aDevice['bmk'], oldBmk);
      expect(terminalDisplayBmk(d, aDevice), 'X1');
      expect(endpointKey(d, portRef(a['id'], '1')), oldKey);
      expect(
        endpointKey(d, portRef(a['id'], '1')),
        isNot(endpointKey(d, portRef(b['id'], '1'))),
      );
      expect(endpointName(d, portRef(a['id'], '1')), 'X1:1');
      expect(endpointName(d, portRef(b['id'], '1')), 'X1:N');
      final roundtrip = validateDrawing(jsonDecode(canonicalJson(d)));
      expect(canonicalJson(roundtrip), canonicalJson(d));
      final rows = documentData(project(d))['terminals'] as List;
      expect(
        rows.map((r) => '${r['bmk']}:${r['terminal']}'),
        containsAll(['X1:1', 'X1:N']),
      );
      expect(
        rows.firstWhere((r) => r['terminal'] == '1')['id'],
        '${aDevice['id']}:1',
      );
    },
  );

  test(
    'renames and marks update display without changing physical identities',
    () {
      final d = emptyDrawing(),
          sheet = objects(d, 'sheets').first['id'] as String;
      final a = addSymbol(d, 'terminal', sheet, 200, 200);
      final strip = createTerminalStrip(d, 'X24');
      assignTerminalToStrip(d, a['deviceId'], strip['id'], 'PE');
      final key = endpointKey(d, portRef(a['id'], '1'));
      renameTerminalStrip(d, strip['id'], 'X100');
      setTerminalMark(d, a['deviceId'], '+');
      expect(endpointName(d, portRef(a['id'], '1')), 'X100:+');
      expect(endpointKey(d, portRef(a['id'], '1')), key);
      expect(validateDrawing(d), d);
    },
  );

  test(
    'duplicate marks per strip and duplicate strip BMKs are rejected without partial changes',
    () {
      final d = emptyDrawing(),
          sheet = objects(d, 'sheets').first['id'] as String;
      final a = addSymbol(d, 'terminal', sheet, 200, 200);
      final b = addSymbol(d, 'terminal', sheet, 400, 200);
      final strip = createTerminalStrip(d, 'X1');
      assignTerminalToStrip(d, a['deviceId'], strip['id'], '1');
      expect(
        () => assignTerminalToStrip(d, b['deviceId'], strip['id'], '1'),
        throwsFormatException,
      );
      expect(
        objectById(d, 'devices', b['deviceId']).containsKey('terminalStripId'),
        false,
      );
      expect(() => createTerminalStrip(d, 'x1'), throwsFormatException);
      expect(
        () => setTerminalMark(d, a['deviceId'], 'four'),
        throwsFormatException,
      );
      expect(
        () => renameTerminalStrip(
          d,
          strip['id'],
          objectById(d, 'devices', b['deviceId'])['bmk'],
        ),
        throwsFormatException,
      );
      expect(validateDrawing(d), d);
    },
  );

  test(
    'validation rejects dangling strip, duplicate marks and nonterminal assignments',
    () {
      final d = emptyDrawing(),
          sheet = objects(d, 'sheets').first['id'] as String;
      final a = addSymbol(d, 'terminal', sheet, 200, 200);
      final b = addSymbol(d, 'terminal', sheet, 400, 200);
      final other = addSymbol(d, 'switch', sheet, 600, 200);
      final strip = createTerminalStrip(d, 'X2');
      assignTerminalToStrip(d, a['deviceId'], strip['id'], 'N');
      assignTerminalToStrip(d, b['deviceId'], strip['id'], 'PE');
      for (final mutate in <void Function(Json)>[
        (v) => objectById(v, 'devices', a['deviceId'])['terminalStripId'] =
            'absent',
        (v) =>
            (objectById(v, 'devices', b['deviceId'])['terminals'] as List)
                    .first['label'] =
                'N',
        (v) => objectById(v, 'devices', other['deviceId'])['terminalStripId'] =
            strip['id'],
        (v) =>
            (objectById(v, 'devices', a['deviceId'])['terminals'] as List)
                    .first['label'] =
                'long',
      ]) {
        final bad = cloneJson(d);
        mutate(bad);
        expect(() => validateDrawing(bad), throwsFormatException);
      }
    },
  );

  test(
    'safe deletion rejects occupied strips and leaves legacy terminals untouched',
    () {
      final d = emptyDrawing(),
          sheet = objects(d, 'sheets').first['id'] as String;
      final a = addSymbol(d, 'terminal', sheet, 200, 200);
      final legacy = endpointName(d, portRef(a['id'], '1'));
      final strip = createTerminalStrip(d, 'X1');
      assignTerminalToStrip(d, a['deviceId'], strip['id'], '2');
      expect(() => deleteTerminalStrip(d, strip['id']), throwsFormatException);
      expect(objects(d, 'terminalStrips'), hasLength(1));
      objectById(d, 'devices', a['deviceId']).remove('terminalStripId');
      deleteTerminalStrip(d, strip['id']);
      expect(endpointName(d, portRef(a['id'], '1')), isNot(legacy));
      expect(validateDrawing(d), d);
      final old = sampleDrawing('motor');
      expect(validateDrawing(old), old);
    },
  );

  test('new device BMKs skip existing strip BMKs', () {
    final d = emptyDrawing(),
        sheet = objects(d, 'sheets').first['id'] as String;
    createTerminalStrip(d, '1-X2');
    final instance = addSymbol(d, 'terminal', sheet, 200, 200);
    expect(objectById(d, 'devices', instance['deviceId'])['bmk'], '1-X2.1');
    expect(validateDrawing(d), d);
  });
}
