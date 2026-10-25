import 'drawing.dart';
import 'library.dart';

/// Macro instances are independent copies with wholly fresh electrical identities.
/// Insert on new sheets so cross-sheet continuations and coil/contact links stay intact.
Json insertMacro(Json target, Json source, {Json? provenance}) {
  final incoming = validateDrawing(source), d = cloneJson(target);
  final keys = [
    'sheets',
    'devices',
    'instances',
    'nodes',
    'continuations',
    'wires',
    'cables',
  ];
  final mappings = {
    for (final k in [...keys, 'symbols']) k: <String, String>{},
  };
  for (final k in mappings.keys) {
    for (final o in (incoming[k] as List? ?? []).cast<Json>())
      mappings[k]![o['id']] = newId();
  }
  var number = objects(
    d,
    'sheets',
  ).map((s) => s['number'] as int).fold(0, (a, b) => a > b ? a : b);
  for (final s in objects(incoming, 'sheets')) {
    (d['sheets'] as List).add({
      ...s,
      'id': mappings['sheets']![s['id']],
      'number': ++number,
    });
  }
  for (final s in (incoming['symbols'] as List? ?? []).cast<Json>()) {
    (d.putIfAbsent('symbols', () => []) as List).add({
      ...s,
      'id': mappings['symbols']![s['id']],
    });
  }
  for (final device in objects(incoming, 'devices')) {
    final first = objects(
      incoming,
      'instances',
    ).where((i) => i['deviceId'] == device['id']).firstOrNull;
    final type = device['type'] as String;
    final code = first == null
        ? 'A'
        : symbolByKey(first['symbol'], incoming).code;
    final sid = first == null
        ? mappings['sheets']!.values.first
        : mappings['sheets']![first['sheetId']]!;
    final copy = {
      ...device,
      'id': mappings['devices']![device['id']],
      'bmk': proposedBmk(d, sid, code, first?['x'] ?? 100),
    };
    if (type.startsWith('custom_'))
      copy['type'] = 'custom_${mappings['symbols']![type.substring(7)]}';
    if (copy['channels'] != null)
      copy['channels'] = [
        for (final c in (copy['channels'] as List).cast<Json>())
          <String, dynamic>{...c, 'module': copy['id']},
      ];
    (d['devices'] as List).add(copy);
  }
  Json reference(Json r) => r['kind'] == 'port'
      ? {...r, 'instanceId': mappings['instances']![r['instanceId']]}
      : {
          ...r,
          'id':
              mappings[r['kind'] == 'node'
                  ? 'nodes'
                  : 'continuations']![r['id']],
        };
  final pairIds = <String, String>{};
  for (final k in ['instances', 'nodes', 'continuations', 'cables', 'wires']) {
    for (final o in objects(incoming, k)) {
      final copy = <String, dynamic>{...o, 'id': mappings[k]![o['id']]};
      if (o.containsKey('sheetId'))
        copy['sheetId'] = mappings['sheets']![o['sheetId']];
      if (k == 'instances') {
        copy['deviceId'] = mappings['devices']![o['deviceId']];
        if ((o['symbol'] as String).startsWith('custom_'))
          copy['symbol'] =
              'custom_${mappings['symbols']![o['symbol'].substring(7)]}';
      }
      if (k == 'continuations')
        copy['linkId'] = pairIds.putIfAbsent(o['linkId'], newId);
      if (k == 'cables') {
        var bmk = '${number}-${o['bmk']}', n = 0;
        while (objects(d, 'cables').any((c) => c['bmk'] == bmk)) {
          bmk = '${number}-${o['bmk']}.${++n}';
        }
        copy['bmk'] = bmk;
      }
      if (k == 'wires') {
        copy['from'] = reference(o['from']);
        copy['to'] = reference(o['to']);
        if (o['cableId'] != null)
          copy['cableId'] = mappings['cables']![o['cableId']];
      }
      (d[k] as List).add(copy);
    }
  }
  final circuitIds = <String, String>{};
  for (final p in (incoming['plans'] as List? ?? []).cast<Json>()) {
    final copy = cloneJson(p)..['id'] = mappings['sheets']![p['id']];
    for (final c in copy['circuits'] ?? []) {
      c['id'] = circuitIds.putIfAbsent(c['id'], newId);
      c['deviceIds'] = [
        for (final id in c['deviceIds']) mappings['devices']![id],
      ];
    }
    for (final r in copy['routes'] ?? []) {
      r['id'] = newId();
      r['from'] = mappings['instances']![r['from']];
      r['to'] = mappings['instances']![r['to']];
      r['circuitId'] = circuitIds[r['circuitId']];
    }
    (d.putIfAbsent('plans', () => []) as List).add(copy);
  }
  final routeIds = <String, String>{};
  for (final p in (incoming['plans'] as List? ?? []).cast<Json>()) {
    final inserted = (d['plans'] as List).cast<Json>().firstWhere(
      (v) => v['id'] == mappings['sheets']![p['id']],
    );
    final oldRoutes = (p['routes'] as List? ?? []),
        newRoutes = (inserted['routes'] as List? ?? []);
    for (var n = 0; n < oldRoutes.length; n++)
      routeIds[oldRoutes[n]['id']] = newRoutes[n]['id'];
  }
  for (final c in (incoming['calculations'] as List? ?? []).cast<Json>()) {
    final copy = cloneJson(c)..['id'] = newId();
    if (c['routeId'] != null) copy['routeId'] = routeIds[c['routeId']];
    if (c['deviceIds'] != null)
      copy['deviceIds'] = [
        for (final id in c['deviceIds']) mappings['devices']![id],
      ];
    (d.putIfAbsent('calculations', () => []) as List).add(copy);
  }
  if (provenance != null)
    (d.putIfAbsent('macroSources', () => []) as List).add({
      'id': newId(),
      'macroId': provenance['id'],
      'version': provenance['version'],
      'name': provenance['name'],
      'origin': provenance['origin'],
      'license': provenance['license'],
      'sheetIds': mappings['sheets']!.values.toList(),
    });
  return validateDrawing(d);
}

Json macroFields(Json body) {
  String text(String key, int max) {
    final v = body[key];
    if (v is! String || v.trim().isEmpty || v.length > max)
      throw FormatException('$key: gültiger Makrotext erforderlich.');
    return v.trim();
  }

  final groups = body['groups'];
  if (groups is! List ||
      groups.length > 12 ||
      groups.any((g) => g is! String || g.trim().isEmpty || g.length > 100))
    throw const FormatException('Makrogruppen: maximal zwölf Namen.');
  final drawing = validateDrawing(body['drawing']);
  if (objects(drawing, 'instances').isEmpty)
    throw const FormatException(
      'Ein Makro braucht mindestens ein Betriebsmittel.',
    );
  return {
    'name': text('name', 160),
    'origin': text('origin', 2000),
    'license': text('license', 1000),
    'groups': groups.toSet().toList(),
    'drawing': drawing,
  };
}

/// A rectangle selects symbol centres on one sheet. Only complete internal wires
/// and nodes are copied, never hidden backgrounds or references outside the box.
Json extractMacroRegion(
  Json source,
  String sheetId,
  num x1,
  num y1,
  num x2,
  num y2,
) {
  final original = validateDrawing(source);
  final left = x1 < x2 ? x1 : x2, right = x1 > x2 ? x1 : x2;
  final top = y1 < y2 ? y1 : y2, bottom = y1 > y2 ? y1 : y2;
  bool inside(Json o) =>
      o['sheetId'] == sheetId &&
      o['x'] >= left &&
      o['x'] <= right &&
      o['y'] >= top &&
      o['y'] <= bottom;
  final instances = objects(original, 'instances').where(inside).toList();
  if (instances.isEmpty)
    throw FormatException('Der Auswahlrahmen enthält keine Bauteile.');
  final deviceIds = instances.map((i) => i['deviceId']).toSet();
  for (final id in deviceIds) {
    final contacts = instances.where(
      (i) =>
          i['deviceId'] == id && symbolByKey(i['symbol'], original).isContact,
    );
    if (contacts.isNotEmpty &&
        !instances.any(
          (i) =>
              i['deviceId'] == id &&
              symbolByKey(i['symbol'], original).role == 'coil',
        )) {
      throw FormatException(
        'Ausgewählte Relaiskontakte benötigen ihre Spule im Rahmen. Für blattübergreifende Gruppen das gesamte Projekt als Makro speichern.',
      );
    }
  }
  final ids = instances.map((i) => i['id']).toSet();
  final nodes = objects(original, 'nodes').where(inside).toList();
  final nodeIds = nodes.map((n) => n['id']).toSet();
  bool included(Json ref) => ref['kind'] == 'port'
      ? ids.contains(ref['instanceId'])
      : ref['kind'] == 'node' && nodeIds.contains(ref['id']);
  final wires = objects(
    original,
    'wires',
  ).where((w) => included(w['from']) && included(w['to'])).toList();
  final cables = objects(
    original,
    'cables',
  ).where((c) => wires.any((w) => w['cableId'] == c['id'])).toList();
  final symbols = instances.map((i) => i['symbol']).toSet();
  final d = emptyDrawing()
    ..['sheets'] = [objectById(original, 'sheets', sheetId)]
    ..['instances'] = instances
    ..['devices'] = objects(
      original,
      'devices',
    ).where((dev) => deviceIds.contains(dev['id'])).toList()
    ..['nodes'] = nodes
    ..['wires'] = wires
    ..['cables'] = cables
    ..['symbols'] = objects(
      original,
      'symbols',
    ).where((s) => symbols.contains('custom_${s['id']}')).toList();
  // Keep the layout scale; source images, routes and calculations are deliberately excluded.
  final plans = (original['plans'] as List? ?? []).cast<Json>().where(
    (p) => p['id'] == sheetId,
  );
  if (plans.isNotEmpty)
    d['plans'] = [
      {
        'id': sheetId,
        'kind': plans.first['kind'],
        if (plans.first['kind'] == 'layout')
          'mmPerUnit': plans.first['mmPerUnit'],
        'circuits': <Json>[],
        'routes': <Json>[],
      },
    ];
  final copy = cloneJson(d);
  for (final dev in objects(
    copy,
    'devices',
  ).where((v) => v['type'] == 'relay')) {
    final used = {
      'A1',
      'A2',
      for (final i in instances.where((i) => i['deviceId'] == dev['id']))
        ...instancePorts(original, i),
    };
    (dev['terminals'] as List).removeWhere((t) => !used.contains(t['id']));
  }
  return validateDrawing(copy);
}
