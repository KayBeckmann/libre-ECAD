import 'dart:convert';
import 'dart:math' as math;
import 'package:image/image.dart' as image;
import 'drawing.dart';

const planKinds = {
  'installation': 'Installationsplan',
  'layout': 'Aufbauzeichnung',
};
Json? planFor(Json d, String sheetId) => (d['plans'] as List? ?? [])
    .cast<Json>()
    .where((p) => p['id'] == sheetId)
    .firstOrNull;

/// Planning data stays inside the same versioned project as the circuit model.
void validatePlanning(Json d) {
  Never fail(String message) => throw FormatException(message);
  void fields(Json v, Set<String> allowed) {
    if (v.keys.any((k) => !allowed.contains(k)))
      fail('Unbekannte Planungsfelder.');
  }

  void positive(
    Object? value,
    String name, {
    num max = 1e6,
    bool zero = false,
  }) {
    if (value is! num ||
        !value.isFinite ||
        value < (zero ? 0 : 0.000001) ||
        value > max)
      fail('$name: ungültiger Wert.');
  }

  void text(Object? value, String name, {int max = 500}) {
    if (value is! String || value.trim().isEmpty || value.length > max)
      fail('$name: Text erforderlich.');
  }

  void point(Object? value) {
    if (value is! Json) fail('Ungültiger Messpunkt.');
    fields(value, {'x', 'y'});
    positive(value['x'], 'X', max: 1200, zero: true);
    positive(value['y'], 'Y', max: 800, zero: true);
  }

  final plans = d['plans'] ?? [];
  if (plans is! List || plans.length > 50) fail('Maximal 50 Planarten.');
  final ids = <String>{};
  final circuits = <String>{};
  final routeIds = <String>{};
  for (final raw in plans) {
    if (raw is! Json) fail('Ungültige Planart.');
    final p = raw;
    fields(p, {
      'id',
      'kind',
      'background',
      'calibration',
      'mmPerUnit',
      'circuits',
      'routes',
    });
    if (!objects(d, 'sheets').any((s) => s['id'] == p['id']) ||
        !ids.add(p['id']) ||
        !planKinds.containsKey(p['kind']))
      fail('Planart oder Blattreferenz ungültig.');
    if (p['kind'] == 'layout')
      positive(p['mmPerUnit'], 'Aufbaumaßstab', max: 1000);
    if (p['background'] != null) {
      final b = p['background'];
      if (b is! Json) fail('Ungültige Bildvorlage.');
      fields(b, {
        'png',
        'origin',
        'revision',
        'locked',
        'x',
        'y',
        'width',
        'height',
      });
      text(b['origin'], 'Bildherkunft');
      text(b['revision'], 'Bildrevision', max: 100);
      if (b['locked'] is! bool ||
          b['png'] is! String ||
          (b['png'] as String).length > 2800000)
        fail('Bildvorlage zu groß oder ungesperrt.');
      final bytes = base64Decode(b['png']);
      if (bytes.length < 24 ||
          bytes[0] != 137 ||
          utf8.decode(bytes.sublist(1, 4), allowMalformed: true) != 'PNG' ||
          bytes[12] != 73 ||
          bytes[13] != 72 ||
          bytes[14] != 68 ||
          bytes[15] != 82)
        fail('Nur PNG-Bildvorlagen.');
      int size(int offset) =>
          bytes[offset] * 16777216 +
          bytes[offset + 1] * 65536 +
          bytes[offset + 2] * 256 +
          bytes[offset + 3];
      if (size(16) < 1 || size(20) < 1 || size(16) > 2400 || size(20) > 2400)
        fail('Bildvorlage: maximal 2400 × 2400 Pixel.');
      try {
        if (image.decodePng(bytes, frame: 0) == null)
          fail('PNG-Bilddaten fehlen.');
      } catch (_) {
        fail('PNG-Bildvorlage beschädigt.');
      }
      for (final key in ['x', 'y'])
        positive(b[key], key, max: 1200, zero: true);
      positive(b['width'], 'Bildbreite', max: 1120);
      positive(b['height'], 'Bildhöhe', max: 640);
      if (b['x'] + b['width'] > 1160 || b['y'] + b['height'] > 700)
        fail('Bild außerhalb des Blatts.');
    }
    if (p['calibration'] != null) {
      final c = p['calibration'];
      if (c is! Json) fail('Ungültiger Maßstab.');
      fields(c, {'a', 'b', 'metres', 'source', 'perspectiveConfirmed'});
      point(c['a']);
      point(c['b']);
      positive(c['metres'], 'Referenzlänge', max: 10000);
      text(c['source'], 'Maßstabsquelle');
      if (c['perspectiveConfirmed'] is! bool || distance(c['a'], c['b']) < 1)
        fail('Zwei verschiedene Messpunkte erforderlich.');
    }
    final cs = p['circuits'] ?? [];
    if (cs is! List || cs.length > 100)
      fail('Maximal 100 Stromkreise je Blatt.');
    for (final c in cs) {
      if (c is! Json) fail('Ungültiger Stromkreis.');
      fields(c, {'id', 'name', 'distribution', 'deviceIds'});
      text(c['id'], 'Stromkreis-ID', max: 80);
      text(c['name'], 'Stromkreis');
      text(c['distribution'], 'Verteilung');
      if (!circuits.add(c['id']) ||
          c['deviceIds'] is! List ||
          (c['deviceIds'] as List).toSet().length != c['deviceIds'].length ||
          (c['deviceIds'] as List).any(
            (id) => !objects(d, 'devices').any((v) => v['id'] == id),
          ))
        fail('Stromkreisgeräte ungültig.');
    }
    final routes = p['routes'] ?? [];
    if (routes is! List || routes.length > 200)
      fail('Maximal 200 Leitungswege je Blatt.');
    for (final r in routes) {
      if (r is! Json) fail('Ungültiger Leitungsweg.');
      fields(r, {
        'id',
        'name',
        'from',
        'to',
        'points',
        'circuitId',
        'allowanceM',
      });
      text(r['id'], 'Weg-ID', max: 80);
      text(r['name'], 'Leitungsweg');
      if (!routeIds.add(r['id']) || !cs.any((c) => c['id'] == r['circuitId']))
        fail('Leitungsweg ohne gültigen Stromkreis.');
      for (final side in ['from', 'to']) {
        if (!objects(
          d,
          'instances',
        ).any((i) => i['id'] == r[side] && i['sheetId'] == p['id']))
          fail('Wegendpunkt fehlt auf dem Blatt.');
      }
      if (r['from'] == r['to'] ||
          r['points'] is! List ||
          r['points'].length > 100)
        fail('Ungültiger Leitungsweg.');
      for (final v in r['points']) point(v);
      positive(r['allowanceM'], 'Längenzuschlag', max: 10000, zero: true);
    }
  }
  final sources = d['macroSources'] ?? [];
  if (sources is! List || sources.length > 100)
    fail('Maximal 100 Makroquellen.');
  final sourceIds = <String>{};
  for (final s in sources) {
    if (s is! Json) fail('Ungültige Makroquelle.');
    fields(s, {
      'id',
      'macroId',
      'version',
      'name',
      'origin',
      'license',
      'sheetIds',
    });
    for (final k in ['id', 'macroId', 'name', 'origin', 'license'])
      text(s[k], k, max: 2000);
    if (!sourceIds.add(s['id']) ||
        s['version'] is! int ||
        s['version'] < 1 ||
        s['sheetIds'] is! List ||
        s['sheetIds'].any(
          (id) => !objects(d, 'sheets').any((v) => v['id'] == id),
        ))
      fail('Ungültige Makroversion oder Blattreferenz.');
  }
  for (final device in objects(d, 'devices')) {
    final channels = device['channels'];
    if (channels != null) {
      if (device['type'] != 'plc' || channels is! List || channels.length > 4)
        fail('Ungültige SPS-Kanäle.');
      final channelIds = <String>{};
      for (final c in channels) {
        if (c is! Json) fail('Ungültiger Kanal.');
        fields(c, {'id', 'module', 'port', 'signal'});
        if (!['I0', 'I1', 'Q0', 'Q1'].contains(c['id']) ||
            !channelIds.add(c['id']) ||
            c['module'] != device['id'] ||
            c['port'] != c['id'] ||
            c['signal'] is! String ||
            c['signal'].length > 160)
          fail('SPS-Kanal / Modul / Signal ungültig.');
      }
    }
    final a = device['article'];
    if (a == null) continue;
    if (a is! Json) fail('Ungültige Artikelzuordnung.');
    fields(a, {
      'id',
      'version',
      'number',
      'name',
      'manufacturer',
      'variant',
      'unit',
      'origin',
      'license',
      'widthMm',
      'heightMm',
      'depthMm',
      'powerLossW',
      'thermalConditions',
    });
    for (final key in ['id', 'number', 'name', 'origin', 'license'])
      text(a[key], key, max: 2000);
    if (a['version'] is! int || a['version'] < 1 || a['unit'] != 'piece')
      fail('Artikelversion/Einheit ungültig.');
    for (final key in ['manufacturer', 'variant', 'thermalConditions']) {
      if (a[key] is! String || a[key].length > 2000)
        fail('Ungültiger Artikeltext.');
    }
    for (final key in ['widthMm', 'heightMm', 'depthMm', 'powerLossW']) {
      if (a[key] != null) positive(a[key], key, zero: key == 'powerLossW');
    }
  }
}

Json articleSnapshot(Json a) => {
  'id': a['id'],
  'version': a['version'],
  'number': a['articleNumber'],
  'name': a['name'],
  'manufacturer': a['manufacturerName'] ?? '',
  'variant': '',
  'unit': 'piece',
  'origin': a['origin'],
  'license': a['license'],
  for (final k in ['widthMm', 'heightMm', 'depthMm'])
    k: a['layers']?['mechanical']?[k],
  'powerLossW': a['layers']?['thermal']?['powerLossW'],
  'thermalConditions': a['layers']?['thermal']?['conditions'] ?? '',
};

double distance(Json a, Json b) => math.sqrt(
  math.pow((b['x'] as num) - (a['x'] as num), 2) +
      math.pow((b['y'] as num) - (a['y'] as num), 2),
);
List<Json> routePoints(Json d, Json route) => [
  objectById(d, 'instances', route['from']),
  ...(route['points'] as List).cast<Json>(),
  objectById(d, 'instances', route['to']),
];
Json routeLength(Json d, Json p, Json route) {
  final c = p['calibration'];
  if (p['kind'] != 'layout' && (c == null || c['perspectiveConfirmed'] != true))
    return {'metres': null, 'reason': 'Maßstab oder Perspektivprüfung fehlt.'};
  final points = routePoints(d, route);
  var units = 0.0;
  for (var n = 1; n < points.length; n++)
    units += distance(points[n - 1], points[n]);
  final factor = p['kind'] == 'layout'
      ? (p['mmPerUnit'] as num) / 1000
      : (c['metres'] as num) / distance(c['a'], c['b']);
  return {
    'metres': units * factor + (route['allowanceM'] as num),
    'drawnMetres': units * factor,
    'allowanceM': route['allowanceM'],
    'metresPerUnit': factor,
    'reason': 'Aus aktuellem Blattmaßstab; Höhen/Reserven nur im Zuschlag.',
  };
}

List<Json> contactTree(Json d, String deviceId) => [
  for (final i in objects(
    d,
    'instances',
  ).where((i) => i['deviceId'] == deviceId))
    {
      'id': i['id'],
      'symbol': i['symbol'],
      'position': positionReference(d, i),
      'ports': instancePorts(d, i),
      'connectedPorts': instancePorts(d, i)
          .where(
            (p) => objects(d, 'wires').any(
              (w) => [
                w['from'],
                w['to'],
              ].any((r) => r['instanceId'] == i['id'] && r['terminalId'] == p),
            ),
          )
          .toList(),
    },
];

Json? layoutRectangle(Json d, Json plan, Json instance) {
  final a = objectById(d, 'devices', instance['deviceId'])['article'];
  if (a == null || a['widthMm'] == null || a['heightMm'] == null) return null;
  final width = (a['widthMm'] as num) / (plan['mmPerUnit'] as num),
      height = (a['heightMm'] as num) / (plan['mmPerUnit'] as num);
  return {
    'x': instance['x'] - width / 2,
    'y': instance['y'] - height / 2,
    'width': width,
    'height': height,
  };
}
