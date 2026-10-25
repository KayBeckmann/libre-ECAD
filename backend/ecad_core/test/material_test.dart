import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'material aggregation counts physical devices once, stable packet IDs and variant/version boundaries',
    () {
      final d = sampleDrawing('motor');
      final article = articleSnapshot({
        'id': 'a',
        'version': 1,
        'articleNumber': 'TEST',
        'name': 'TEST Gerät',
        'origin': 'Own',
        'license': 'CC0',
        'layers': {},
      });
      for (final dev in objects(d, 'devices'))
        dev['article'] = cloneJson(article);
      final project = <String, dynamic>{
        'id': 'p',
        'name': 'Project',
        'version': 3,
        'drawing': d,
      };
      final packet = materialPacket(project, source: 'http://test.invalid');
      expect(packet['items'], hasLength(1));
      expect(packet['items'][0]['quantity'], objects(d, 'devices').length);
      final reordered = jsonDecode(canonicalJson(project)) as Json;
      expect(
        materialPacket(reordered, source: 'http://test.invalid')['packetId'],
        packet['packetId'],
      );
      objects(d, 'devices')[0]['article']['version'] = 2;
      expect(
        materialPacket(project, source: 'http://test.invalid')['items'],
        hasLength(2),
      );
      expect(
        materialPacket(project, source: 'http://test.invalid')['packetId'],
        isNot(packet['packetId']),
      );
      objects(d, 'devices')[0].remove('article');
      expect(
        materialPacket(project, source: 'http://test.invalid')['unassigned'],
        hasLength(1),
      );
      objects(d, 'devices')[1]['article']['name'] = 'inconsistent';
      expect(
        () => materialPacket(project, source: 'http://test.invalid'),
        throwsFormatException,
      );
    },
  );
}
