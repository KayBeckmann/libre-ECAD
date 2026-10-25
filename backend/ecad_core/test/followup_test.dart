import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'contacts reference only their coil, comb stays below coil and follows moved references',
    () {
      final d = sampleDrawing('three-phase');
      final coil = objects(
        d,
        'instances',
      ).firstWhere((i) => symbolByKey(i['symbol'], d).role == 'coil');
      final contacts = instanceReferences(d, coil);
      expect(contacts, hasLength(3));
      for (final r in contacts) {
        final i = objectById(d, 'instances', r['instanceId']);
        expect(instanceReferences(d, i).map((v) => v['instanceId']), [
          coil['id'],
        ]);
      }
      final comb = relayContactComb(d, coil);
      expect(comb.map((c) => c['role']).toSet(), {'nc', 'no'});
      expect(comb.every((c) => c['y'] > coil['y']), isTrue);
      expect(comb.every((c) => (c['terminals'] as List).length == 2), isTrue);
      final first = objectById(d, 'instances', contacts.first['instanceId']);
      first['x'] = 1000;
      expect(
        relayContactComb(
          d,
          coil,
        ).firstWhere((c) => c['instanceId'] == first['id'])['position'],
        positionReference(d, first),
      );
    },
  );
  test(
    'rectangle copies only selected devices and complete internal connections',
    () {
      final d = emptyDrawing(),
          sid = objects(emptyDrawing(), 'sheets').first['id'];
      d['sheets'] = [
        {'id': sid, 'number': 1, 'title': 'Selection'},
      ];
      final a = addSymbol(d, 'coil', sid, 200, 200);
      final b = addSymbol(d, 'contact', sid, 400, 200, deviceId: a['deviceId']);
      final c = addSymbol(
        d,
        'contact_nc',
        sid,
        800,
        200,
        deviceId: a['deviceId'],
      );
      d['wires'] = [
        {
          'id': newId(),
          'sheetId': sid,
          'from': portRef(a['id'], 'A1'),
          'to': portRef(b['id'], instancePorts(d, b).first),
        },
        {
          'id': newId(),
          'sheetId': sid,
          'from': portRef(b['id'], instancePorts(d, b).last),
          'to': portRef(c['id'], instancePorts(d, c).first),
        },
      ];
      final before = canonicalJson(d);
      final macro = extractMacroRegion(d, sid, 100, 100, 500, 300);
      expect(objects(macro, 'instances'), hasLength(2));
      expect(objects(macro, 'devices'), hasLength(1));
      expect(objects(macro, 'wires'), hasLength(1));
      expect(
        instanceReferences(macro, objects(macro, 'instances').first),
        hasLength(1),
      );
      expect(
        canonicalJson(extractMacroRegion(d, sid, 500, 300, 100, 100)),
        canonicalJson(macro),
      );
      expect(canonicalJson(d), before);
      final inserted = insertMacro(insertMacro(emptyDrawing(), macro), macro);
      expect(objects(inserted, 'devices'), hasLength(2));
      expect(
        objects(inserted, 'instances').map((i) => i['deviceId']).toSet(),
        hasLength(2),
      );
      expect(
        () => extractMacroRegion(d, sid, 350, 150, 450, 250),
        throwsFormatException,
      );
      expect(
        () => extractMacroRegion(d, sid, 0, 0, 20, 20),
        throwsFormatException,
      );
    },
  );
  test(
    'region keeps layout scale but no private background or source history',
    () {
      final d = emptyDrawing(), sid = objects(d, 'sheets').first['id'];
      addSymbol(d, 'motor', sid, 200, 200);
      d['plans'] = [
        {
          'id': sid,
          'kind': 'layout',
          'mmPerUnit': 2,
          'circuits': <Json>[],
          'routes': <Json>[],
        },
      ];
      final result = extractMacroRegion(d, sid, 0, 0, 1200, 800);
      expect(result['plans'].first['mmPerUnit'], 2);
      expect(result.containsKey('macroSources'), false);
      expect(result.containsKey('calculations'), false);
      expect(result['plans'].first.containsKey('background'), false);
    },
  );
}
