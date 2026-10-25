import 'calculations.dart';
import 'planning.dart';
import 'drawing.dart';
import 'library.dart';

/// The same immutable input feeds tables, checks and printed documents.
Json documentData(Json project) {
  final d = validateDrawing(project['drawing']);
  final sheets = objects(d, 'sheets')
    ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
  final connections =
      <Json>[
        for (final w in objects(d, 'wires'))
          {
            'id': w['id'],
            if (w['conductor'] != null) 'conductor': w['conductor'],
            'sheet': objectById(d, 'sheets', w['sheetId'])['number'],
            'from': endpointName(d, w['from']),
            'to': endpointName(d, w['to']),
            'cable': w['cableId'] == null
                ? ''
                : objectById(d, 'cables', w['cableId'])['bmk'],
            'core': w['coreId'] == null
                ? ''
                : (objectById(d, 'cables', w['cableId'])['cores'] as List)
                      .firstWhere((c) => c['id'] == w['coreId'])['label'],
          },
      ]..sort(
        (a, b) => '${a['sheet']}/${a['from']}/${a['to']}'.compareTo(
          '${b['sheet']}/${b['from']}/${b['to']}',
        ),
      );
  final material = [
    for (final device in objects(d, 'devices'))
      {
        'id': device['id'],
        'bmk': device['bmk'],
        'label': device['label'],
        'type': device['type'],
        'quantity': 1,
        if (device['article'] != null) 'article': device['article'],
        'positions': objects(d, 'instances')
            .where((i) => i['deviceId'] == device['id'])
            .map((i) => positionReference(d, i))
            .join(', '),
      },
  ]..sort((a, b) => (a['bmk'] as String).compareTo(b['bmk'] as String));
  return {
    'version': project['version'],
    'projectId': project['id'],
    'name': project['name'],
    'description': project['description'],
    'metadata': project['metadata'] ?? <String, dynamic>{},
    'calculations': [
      for (final c in (d['calculations'] as List? ?? []).cast<Json>())
        calculate(d, c),
    ],
    'sheets': sheets,
    'connections': connections,
    'material': material,
    'terminals': [
      for (final dev in objects(
        d,
        'devices',
      ).where((v) => v['type'] == 'terminal'))
        for (final t in dev['terminals'])
          {
            'id': '${dev['id']}:${t['id']}',
            'bmk': dev['bmk'],
            'terminal': t['label'],
            'connections': connections
                .where(
                  (w) =>
                      w['from'] == '${dev['bmk']}:${t['label']}' ||
                      w['to'] == '${dev['bmk']}:${t['label']}',
                )
                .map((w) => '${w['from']} -> ${w['to']}')
                .join('; '),
          },
    ],
    'cables': [
      for (final c in objects(d, 'cables'))
        for (final core in c['cores'])
          {
            'id': '${c['id']}:${core['id']}',
            'bmk': c['bmk'],
            'core': core['label'],
            'color': core['color'],
            'connections': connections
                .where(
                  (w) => w['cable'] == c['bmk'] && w['core'] == core['label'],
                )
                .map((w) => '${w['from']} -> ${w['to']}')
                .join('; '),
          },
    ],
  };
}

String endpointName(Json d, Json ref) {
  if (ref['kind'] == 'port') {
    final i = objectById(d, 'instances', ref['instanceId']);
    final dev = objectById(d, 'devices', i['deviceId']);
    final t = (dev['terminals'] as List).firstWhere(
      (t) => t['id'] == ref['terminalId'],
    );
    return '${dev['bmk']}:${t['label']}';
  }
  final o = objectById(
    d,
    ref['kind'] == 'node' ? 'nodes' : 'continuations',
    ref['id'],
  );
  return ref['kind'] == 'node'
      ? 'Knoten ${o['id']}'
      : 'Fortsetzung ${o['label']}';
}

/// Engineering aids for this synthetic library, never a standards assessment.
/// Structural errors cannot be waived. Warnings require a reason for this version.
List<Json> drawingFindings(Object? input) {
  Json d;
  try {
    d = validateDrawing(input);
  } on FormatException catch (e) {
    Json? culprit;
    if (input is Json) {
      List<Json> safe(String key) => input[key] is List
          ? (input[key] as List).whereType<Json>().toList()
          : [];
      final instances = safe('instances'), devices = safe('devices');
      final bmks = <Object?>{};
      for (final dev in devices) {
        if (!bmks.add(dev['bmk'])) {
          culprit =
              instances.where((i) => i['deviceId'] == dev['id']).firstOrNull ??
              dev;
          break;
        }
      }
      culprit ??= instances
          .where((i) => !devices.any((dev) => dev['id'] == i['deviceId']))
          .firstOrNull;
      if (culprit == null) {
        for (final w in safe('wires')) {
          try {
            endpointPosition(input, w['from']);
            endpointPosition(input, w['to']);
          } on FormatException {
            culprit = w;
            break;
          } on TypeError {
            culprit = w;
            break;
          }
        }
      }
    }
    return [
      {
        'id': 'structure:${culprit?['id'] ?? 'drawing'}',
        'severity': 'error',
        'message': e.message,
        'objectId': culprit?['id'] ?? '',
        'sheetId': culprit?['sheetId'] ?? '',
      },
    ];
  }
  final result = <Json>[];
  void add(String code, String message, Json object, {String? suffix}) =>
      result.add({
        'id': '$code:${object['id']}${suffix == null ? '' : ':$suffix'}',
        'severity': 'warning',
        'message': message,
        'objectId': object['id'],
        'sheetId': object['sheetId'] ?? '',
      });
  if (objects(d, 'instances').isEmpty)
    add(
      'empty',
      'Projekt enthält keine Betriebsmittel.',
      objects(d, 'sheets').first,
    );
  final usage = <String, int>{};
  for (final w in objects(d, 'wires')) {
    for (final ref in [w['from'], w['to']]) {
      final key = endpointKey(d, ref);
      usage[key] = (usage[key] ?? 0) + 1;
    }
  }
  final seen = <String>{};
  for (final i in objects(d, 'instances')) {
    final dev = objectById(d, 'devices', i['deviceId']);
    for (final port in instancePorts(d, i)) {
      final key = endpointKey(d, portRef(i['id'], port));
      if (!seen.add(key)) continue;
      final count = usage[key] ?? 0;
      if (count == 0)
        add(
          'open',
          '${dev['bmk']}:$port ist offen. Absicht prüfen.',
          i,
          suffix: port,
        );
      if (count > 1 && dev['type'] != 'terminal')
        add(
          'occupied',
          '${dev['bmk']}:$port hat $count Verbindungen. Mehrfachbelegung prüfen.',
          i,
          suffix: port,
        );
    }
  }
  for (final device in objects(
    d,
    'devices',
  ).where((v) => v['type'] == 'relay')) {
    final views = objects(
      d,
      'instances',
    ).where((i) => i['deviceId'] == device['id']).toList();
    final coils = views
        .where((i) => symbolByKey(i['symbol'], d).role == 'coil')
        .toList();
    if (coils.length != 1 && views.isNotEmpty)
      add(
        'relay-coil',
        coils.isEmpty
            ? '${device['bmk']}: Kontakte ohne zugeordnete Spule.'
            : '${device['bmk']}: Mehrere Spulendarstellungen prüfen.',
        views.first,
      );
  }
  for (final kind in ['nodes', 'continuations']) {
    for (final o in objects(d, kind)) {
      // Continuations have one logical key for both ends: inspect local wires.
      final count = objects(d, 'wires')
          .where((w) => [w['from'], w['to']].any((ref) => ref['id'] == o['id']))
          .length;
      if (count < (kind == 'nodes' ? 2 : 1))
        add(
          'dangling',
          kind == 'nodes'
              ? 'Knoten ist nicht durchgehend verbunden.'
              : 'Fortsetzung hat keine lokale Verbindung.',
          o,
        );
    }
  }
  for (final net in nets(d)) {
    final wires = objects(
      d,
      'wires',
    ).where((w) => (net['wireIds'] as List).contains(w['id'])).toList();
    final names = wires.map((w) => w['conductor']).whereType<String>().toSet();
    if (names.length > 1)
      add(
        'conductor-conflict',
        'Verschiedene Leiterkennzeichnungen im selben Netz: ${names.join(', ')}.',
        wires.first,
      );
  }
  for (final c in (d['calculations'] as List? ?? []).cast<Json>()) {
    final value = calculate(d, c);
    add(
      'calculation',
      '${c['name']}: ${value['status'] == 'incomplete' ? 'Rechenfall unvollständig' : 'Rechenvorschlag ungeprüft'}. ${(value['messages'] as List).join(' ')}',
      c,
    );
  }
  for (final p in (d['plans'] as List? ?? []).cast<Json>()) {
    final sheet = {'id': p['id'], 'sheetId': p['id']};
    if (p['kind'] == 'installation' &&
        (p['calibration'] == null ||
            p['calibration']['perspectiveConfirmed'] != true))
      add(
        'scale',
        'Maßstab oder Perspektivprüfung fehlt; keine belastbare Leitungslänge.',
        sheet,
      );
    if (p['background']?['locked'] == false)
      add('background', 'Bildvorlage ist zum Ausrichten entsperrt.', sheet);
    if (p['kind'] == 'layout') {
      final views = objects(
        d,
        'instances',
      ).where((i) => i['sheetId'] == p['id']).toList();
      for (var n = 0; n < views.length; n++) {
        final i = views[n], r = layoutRectangle(d, p, i);
        if (r == null) {
          add('dimensions', 'Artikelmaße für Aufbauzeichnung fehlen.', i);
          continue;
        }
        if (r['x'] < 40 ||
            r['y'] < 60 ||
            r['x'] + r['width'] > 1160 ||
            r['y'] + r['height'] > 700)
          add('layout-bounds', 'Gerät ragt über die Zeichenfläche.', i);
        for (final other in views.take(n)) {
          final q = layoutRectangle(d, p, other);
          if (q != null &&
              r['x'] < q['x'] + q['width'] &&
              r['x'] + r['width'] > q['x'] &&
              r['y'] < q['y'] + q['height'] &&
              r['y'] + r['height'] > q['y'])
            add(
              'layout-overlap',
              'Geräteflächen überlappen.',
              i,
              suffix: other['id'],
            );
        }
      }
    }
  }
  return result
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
}

Json pinnedLibrary() => {
  'version': 'libre-ecad-synthetic-3',
  'license': 'MIT',
  'images': <String>[],
  'symbols': [
    for (final s in symbolLibrary)
      {
        'id': s.key,
        'name': s.name,
        'type': s.deviceType,
        'ports': s.ports,
        'allPorts': s.allPorts,
        'role': s.role,
        'pins': symbolPins(s),
        'geometry': symbolGeometry(s),
      },
  ],
};

/// V1 has the same physical pins; the new library only extends its symbol set.
bool supportsLibrary(Object? raw) {
  if (raw is! Json) return false;
  if (canonicalJson(raw) == canonicalJson(pinnedLibrary())) return true;
  if (![
        'libre-ecad-synthetic-1',
        'libre-ecad-synthetic-2',
      ].contains(raw['version']) ||
      raw['symbols'] is! List)
    return false;
  final ids = {
    'supply',
    'breaker',
    'terminal',
    'switch',
    'coil',
    'contact',
    'motor',
    if (raw['version'] == 'libre-ecad-synthetic-2') ...[
      'contact_nc',
      'supply3',
      'breaker3',
    ],
  };
  final entries = raw['symbols'] as List;
  if (entries.length != ids.length ||
      entries.any((e) => e is! Json || !ids.contains(e['id'])) ||
      entries.map((e) => e['id']).toSet().length != ids.length)
    return false;
  for (final e in entries) {
    final s = symbolByKey(e['id']);
    if (e['type'] != s.deviceType ||
        canonicalJson({'ports': e['ports'], 'allPorts': e['allPorts']}) !=
            canonicalJson({'ports': s.ports, 'allPorts': s.allPorts}))
      return false;
  }
  return true;
}

List<Json> drawingChanges(Json before, Json after) => [
  for (final kind in [
    'symbols',
    'plans',
    'macroSources',
    'calculations',
    'sheets',
    'devices',
    'instances',
    'nodes',
    'continuations',
    'wires',
    'cables',
  ])
    for (final id in {
      ...(before[kind] as List? ?? []).cast<Json>().map((o) => o['id']),
      ...(after[kind] as List? ?? []).cast<Json>().map((o) => o['id']),
    })
      ...(() {
        final a = (before[kind] as List? ?? [])
            .cast<Json>()
            .where((o) => o['id'] == id)
            .firstOrNull;
        final b = (after[kind] as List? ?? [])
            .cast<Json>()
            .where((o) => o['id'] == id)
            .firstOrNull;
        if (a != null && b != null && canonicalJson(a) == canonicalJson(b))
          return <Json>[];
        return <Json>[
          {
            'kind': kind,
            'id': id,
            'change': a == null
                ? 'added'
                : b == null
                ? 'removed'
                : 'changed',
            'before': a,
            'after': b,
          },
        ];
      })(),
];
