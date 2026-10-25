import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test('custom contact port ordering does not change physical identity', () {
    final d = emptyDrawing();
    final definition = symbolTemplate('contact', 'reversed');
    definition['ports'] = (definition['ports'] as List).reversed.toList();
    d['symbols'] = [definition];
    final sid = objects(d, 'sheets').first['id'];
    final coil = addSymbol(d, 'coil', sid, 200, 200);
    final contact = addSymbol(
      d,
      'custom_reversed',
      sid,
      400,
      200,
      deviceId: coil['deviceId'],
    );
    expect(contact['portMap'], {'13': '13', '14': '14'});
    expect(validateDrawing(d), d);
    final restored = validateDrawing(jsonDecode(canonicalJson(d)));
    expect(
      endpointPosition(restored, portRef(contact['id'], '13')),
      endpointPosition(d, portRef(contact['id'], '13')),
    );
  });
  test('multiple NO and NC contacts share coil identity but never poles', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first;
    final sid = sheet['id'];
    final coil = addSymbol(d, 'coil', sid, 200, 200);
    final no = addSymbol(
      d,
      'contact',
      sid,
      400,
      200,
      deviceId: coil['deviceId'],
    );
    final nc = addSymbol(
      d,
      'contact_nc',
      sid,
      600,
      200,
      deviceId: coil['deviceId'],
    );
    final second = addSymbol(
      d,
      'contact',
      sid,
      800,
      200,
      deviceId: coil['deviceId'],
    );
    expect(instancePorts(d, no), ['13', '14']);
    expect(instancePorts(d, nc), ['21', '22']);
    expect(instancePorts(d, second), ['33', '34']);
    expect(crossReferences(d, coil['deviceId']), hasLength(4));
    final keys = [
      for (final i in objects(d, 'instances'))
        for (final p in instancePorts(d, i))
          endpointKey(d, portRef(i['id'], p)),
    ];
    expect(keys.toSet().length, 8);
    expect(nets(d), hasLength(8));
    expect(
      canonicalJson(validateDrawing(jsonDecode(canonicalJson(d)))),
      canonicalJson(d),
    );
    final invalid = cloneJson(d);
    invalid['instances'][3]['portMap'] = {'13': '13', '14': '14'};
    expect(() => validateDrawing(invalid), throwsFormatException);
    final wrong = cloneJson(d);
    wrong['instances'][1]['portMap'] = {'13': '21', '14': '22'};
    expect(() => validateDrawing(wrong), throwsFormatException);
  });
  test(
    'marrying a wired contact remaps endpoints without losing wire or view IDs',
    () {
      final d = emptyDrawing(),
          sid = objects(emptyDrawing(), 'sheets').first['id'];
      d['sheets'] = [
        {'id': sid, 'number': 1, 'title': 'Test'},
      ];
      final coil = addSymbol(d, 'coil', sid, 200, 200),
          a = addSymbol(d, 'contact', sid, 400, 200, deviceId: null),
          terminal = addSymbol(d, 'terminal', sid, 600, 200);
      addSymbol(d, 'contact', sid, 800, 400, deviceId: coil['deviceId']);
      d['wires'] = [
        {
          'id': 'wire',
          'sheetId': sid,
          'from': portRef(a['id'], '13'),
          'to': portRef(terminal['id'], '1'),
        },
      ];
      expect(
        drawingFindings(d).any((f) => f['id'].startsWith('relay-coil:')),
        isTrue,
      );
      final old = a['deviceId'];
      assignContact(d, a['id'], coil['deviceId']);
      expect(a['deviceId'], coil['deviceId']);
      expect(d['wires'][0]['from']['terminalId'], '23');
      expect(d['wires'][0]['id'], 'wire');
      expect(objects(d, 'devices').any((v) => v['id'] == old), isFalse);
      expect(
        drawingFindings(d).any((f) => f['id'].startsWith('relay-coil:')),
        isFalse,
      );
      expect(validateDrawing(d), d);
    },
  );
  test(
    'three-phase poles and conductor labels remain separate and survive export',
    () {
      final d = threePhaseDrawing();
      expect(objects(d, 'wires'), hasLength(7));
      final data = documentData({
        'id': 'p',
        'name': 'Test',
        'version': 1,
        'drawing': d,
      });
      expect(
        (data['connections'] as List).where((w) => w['conductor'] == 'L1'),
        hasLength(2),
      );
      final supply = objects(
        d,
        'instances',
      ).firstWhere((i) => i['symbol'] == 'supply3');
      expect(
        endpointPosition(d, portRef(supply['id'], 'L1')),
        isNot(endpointPosition(d, portRef(supply['id'], 'L2'))),
      );
      expect(
        drawingFindings(
          d,
        ).where((f) => f['id'].startsWith('conductor-conflict:')),
        isEmpty,
      );
      final w = objects(d, 'wires')[0];
      (d['wires'] as List).add({
        'id': newId(),
        'sheetId': w['sheetId'],
        'from': w['from'],
        'to': objects(d, 'wires')[2]['from'],
        'conductor': 'L2',
      });
      expect(
        drawingFindings(
          d,
        ).where((f) => f['id'].startsWith('conductor-conflict:')),
        isNotEmpty,
      );
    },
  );
  test(
    'custom vectors are validated and project pins immutable article snapshots',
    () {
      for (final s in symbolLibrary) {
        expect(validateSymbol(symbolTemplate(s.key, newId())), isNotNull);
      }
      final symbol = symbolTemplate('switch', 'symbol');
      final article = <String, dynamic>{
        'id': 'article=',
        'version': 1,
        'origin': 'Own test',
        'layers': {
          'symbol': {'definition': symbol, 'license': 'MIT'},
        },
      };
      final d = emptyDrawing();
      final key = pinArticleSymbol(d, article);
      addSymbol(d, key, objects(d, 'sheets').first['id'], 400, 400);
      final before = canonicalJson(d);
      symbol['primitives'][0]['x'] = 100;
      expect(canonicalJson(d), before);
      expect(pinArticleSymbol(d, article), key);
      article['version'] = 2;
      expect(pinArticleSymbol(d, article), isNot(key));
      expect(objects(d, 'symbols'), hasLength(2));
      expect(drawingChanges(jsonDecode(before), d).single['kind'], 'symbols');
      expect(
        canonicalJson(validateDrawing(jsonDecode(canonicalJson(d)))),
        canonicalJson(d),
      );
      final bad = symbolTemplate('switch', 'bad');
      bad['primitives'].add({'kind': 'svg', 'url': 'https://invalid'});
      expect(() => validateSymbol(bad), throwsFormatException);
      final duplicate = symbolTemplate('switch', 'bad');
      duplicate['ports'][1]['id'] = '1';
      expect(() => validateSymbol(duplicate), throwsFormatException);
      final unmapped = cloneJson(d);
      unmapped['instances'][0]['portMap'] = {'1': '2', '2': '1'};
      expect(() => validateDrawing(unmapped), throwsFormatException);
    },
  );
  test(
    'old pinned libraries remain readable without silently accepting unknown pins',
    () {
      final current = pinnedLibrary(), legacy = cloneJson(current);
      legacy['version'] = 'libre-ecad-synthetic-1';
      legacy['symbols'] = (legacy['symbols'] as List)
          .where(
            (s) => [
              'supply',
              'breaker',
              'terminal',
              'switch',
              'coil',
              'contact',
              'motor',
            ].contains(s['id']),
          )
          .toList();
      expect(supportsLibrary(legacy), isTrue);
      legacy['symbols'][0]['ports'] = ['invalid'];
      expect(supportsLibrary(legacy), isFalse);
    },
  );
}
