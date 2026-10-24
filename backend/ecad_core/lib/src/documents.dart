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
    for (final port in symbolByKey(i['symbol']).ports) {
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
  return result
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
}

Json pinnedLibrary() => {
  'version': 'libre-ecad-synthetic-1',
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
      },
  ],
};

List<Json> drawingChanges(Json before, Json after) => [
  for (final kind in [
    'sheets',
    'devices',
    'instances',
    'nodes',
    'continuations',
    'wires',
    'cables',
  ])
    for (final id in {
      ...objects(before, kind).map((o) => o['id']),
      ...objects(after, kind).map((o) => o['id']),
    })
      ...(() {
        final a = objects(before, kind).where((o) => o['id'] == id).firstOrNull;
        final b = objects(after, kind).where((o) => o['id'] == id).firstOrNull;
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
