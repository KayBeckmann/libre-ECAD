import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'drawing.dart';

/// Exchange preview: no prices, stock booking or order mutations.
Json materialPacket(Json project, {required String source}) {
  final d = validateDrawing(project['drawing']),
      rows = <String, Json>{},
      unassigned = <Json>[];
  for (final dev in objects(d, 'devices')) {
    final a = dev['article'];
    if (a == null) {
      unassigned.add({
        'deviceId': dev['id'],
        'bmk': dev['bmk'],
        'label': dev['label'],
        'reason': 'Kein beschaffbarer Artikel zugeordnet.',
      });
      continue;
    }
    final key = sha256
        .convert(
          utf8.encode(
            canonicalJson({
              'articleId': a['id'],
              'articleVersion': a['version'],
              'variant': a['variant'],
              'unit': a['unit'],
            }),
          ),
        )
        .toString();
    final row = rows.putIfAbsent(
      key,
      () => {
        'id': key,
        'articleId': a['id'],
        'articleVersion': a['version'],
        'articleNumber': a['number'],
        'name': a['name'],
        'manufacturer': a['manufacturer'],
        'variant': a['variant'],
        'unit': a['unit'],
        'quantity': 0,
        'origin': a['origin'],
        'license': a['license'],
        'deviceIds': <String>[],
        'bmks': <String>[],
      },
    );
    if (row['articleNumber'] != a['number'] ||
        row['name'] != a['name'] ||
        row['manufacturer'] != a['manufacturer'])
      throw const FormatException(
        'Widersprüchliche Daten derselben Artikelversion. Artikelzuordnungen prüfen.',
      );
    row['quantity']++;
    (row['deviceIds'] as List).add(dev['id']);
    (row['bmks'] as List).add(dev['bmk']);
  }
  for (final r in rows.values) {
    (r['deviceIds'] as List).sort();
    (r['bmks'] as List).sort();
  }
  final items = rows.values.toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  unassigned.sort(
    (a, b) => (a['deviceId'] as String).compareTo(b['deviceId'] as String),
  );
  final packet = <String, dynamic>{
    'schema': 'libre-ecad.material.v1',
    'source': source,
    'projectId': project['id'],
    'projectName': project['name'],
    'projectVersion': project['version'],
    'drawingSha256': sha256.convert(utf8.encode(canonicalJson(d))).toString(),
    'status': 'planned-unapproved',
    'items': items,
    'unassigned': unassigned,
  };
  packet['packetId'] = sha256
      .convert(utf8.encode(canonicalJson(packet)))
      .toString();
  return packet;
}
