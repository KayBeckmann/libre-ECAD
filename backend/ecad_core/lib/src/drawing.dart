import 'calculations.dart';
import 'planning.dart';
import 'dart:convert';
import 'dart:math';
import 'library.dart';

typedef Json = Map<String, dynamic>;

Json cloneJson(Json value) => jsonDecode(jsonEncode(value)) as Json;
String newId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Json emptyDrawing() => {
  'schemaVersion': 1,
  'sheets': <Json>[
    {'id': newId(), 'number': 1, 'title': 'Stromlaufplan'},
  ],
  'devices': <Json>[],
  'instances': <Json>[],
  'nodes': <Json>[],
  'continuations': <Json>[],
  'wires': <Json>[],
  'cables': <Json>[],
};

List<Json> objects(Json d, String key) =>
    ((key == 'symbols' ? d[key] ?? const <Json>[] : d[key]) as List)
        .cast<Json>();
Json objectById(Json d, String kind, String id) => objects(d, kind).firstWhere(
  (o) => o['id'] == id,
  orElse: () => throw FormatException('$kind: Referenz $id fehlt.'),
);

/// Sorted keys and object IDs make exports independent of map/list insertion order.
String canonicalJson(Json d) {
  Object? sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(value[k])};
    }
    if (value is List) {
      final items = [...value];
      if (items.isNotEmpty &&
          items.every((v) => v is Map && v['id'] is String)) {
        items.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      }
      return items.map(sorted).toList();
    }
    return value;
  }

  return '${const JsonEncoder.withIndent('  ').convert(sorted(d))}\n';
}

int columnFor(num x) => ((x - 40) ~/ 112 + 1).clamp(1, 10);
String positionReference(Json d, Json instance) {
  final sheet = objectById(d, 'sheets', instance['sheetId']);
  final row = (((instance['y'] as num) - 60) ~/ 100).clamp(0, 5);
  return '${sheet['number']}/${String.fromCharCode(65 + row)}${columnFor(instance['x'])}';
}

String proposedBmk(
  Json d,
  String sheetId,
  String code,
  num x, {
  String? exceptDevice,
}) {
  final sheet = objectById(d, 'sheets', sheetId);
  final base = '${sheet['number']}-$code${columnFor(x)}';
  final used = objects(
    d,
    'devices',
  ).where((v) => v['id'] != exceptDevice).map((v) => v['bmk']).toSet();
  var result = base, index = 0;
  while (used.contains(result)) {
    result = '$base.${++index}';
  }
  return result;
}

Json addSymbol(
  Json d,
  String key,
  String sheetId,
  num x,
  num y, {
  String? deviceId,
}) {
  final symbol = symbolByKey(key, d);
  Json device;
  if (deviceId == null) {
    device = {
      'id': newId(),
      'bmk': proposedBmk(d, sheetId, symbol.code, x),
      'label': symbol.name,
      'type': symbol.deviceType,
      'terminals': [
        for (final p
            in symbol.deviceType == 'relay' ? ['A1', 'A2'] : symbol.allPorts)
          {
            'id': p,
            'label':
                symbolPins(
                  symbol,
                ).where((pin) => pin['id'] == p).firstOrNull?['label'] ??
                p,
          },
      ],
    };
    (d['devices'] as List).add(device);
  } else {
    device = objectById(d, 'devices', deviceId);
    if (device['type'] != symbol.deviceType)
      throw FormatException('Darstellung passt nicht zum Gerät.');
  }
  final mapping = symbol.isContact
      ? allocateContact(d, device, symbol)
      : <String, String>{};
  final instance = <String, dynamic>{
    'id': newId(),
    'deviceId': device['id'],
    'sheetId': sheetId,
    'symbol': key,
    if (mapping.isNotEmpty) 'portMap': mapping,
    'x': x,
    'y': y,
  };
  (d['instances'] as List).add(instance);
  return instance;
}

List<String> instancePorts(Json d, Json i) => [
  for (final p in symbolByKey(i['symbol'], d).ports)
    (i['portMap'] as Map?)?[p] as String? ?? p,
];

Map<String, String> allocateContact(
  Json d,
  Json device,
  SymbolDefinition symbol,
) {
  final used = objects(d, 'instances')
      .where(
        (i) =>
            i['deviceId'] == device['id'] &&
            symbolByKey(i['symbol'], d).isContact,
      )
      .expand((i) => instancePorts(d, i))
      .toSet();
  var n = 1;
  while (used.any((p) => RegExp('^$n[1-4]\$').hasMatch(p))) {
    n++;
  }
  final suffix = symbol.role == 'no' ? ['3', '4'] : ['1', '2'];
  final mapping = {
    for (final digit in suffix)
      '${symbol.role == 'no' ? 1 : 2}$digit': '$n$digit',
  };
  final terminals = device['terminals'] as List;
  for (final id in mapping.values) {
    if (!terminals.any((t) => t['id'] == id))
      terminals.add({'id': id, 'label': id});
  }
  return mapping;
}

/// Reassign a physical contact, retaining its view and wire IDs. Its poles get
/// fresh terminal identities on the target relay; no two contacts are shorted.
void assignContact(Json d, String instanceId, String targetDeviceId) {
  final i = objectById(d, 'instances', instanceId),
      target = objectById(d, 'devices', targetDeviceId);
  final symbol = symbolByKey(i['symbol'], d);
  if (!symbol.isContact ||
      target['type'] != 'relay' ||
      !objects(d, 'instances').any(
        (v) =>
            v['deviceId'] == targetDeviceId &&
            symbolByKey(v['symbol'], d).role == 'coil',
      ))
    throw FormatException('Einen Kontakt und ein Relais mit Spule auswählen.');
  if (i['deviceId'] == targetDeviceId) return;
  final oldDevice = i['deviceId'],
      oldPorts = instancePorts(d, i),
      mapping = allocateContact(d, target, symbol);
  final nextPorts = symbol.ports.map((p) => mapping[p]!).toList();
  for (final w in objects(d, 'wires')) {
    for (final side in ['from', 'to']) {
      final ref = w[side] as Json;
      if (ref['kind'] == 'port' && ref['instanceId'] == instanceId)
        ref['terminalId'] = nextPorts[oldPorts.indexOf(ref['terminalId'])];
    }
  }
  i['deviceId'] = targetDeviceId;
  i['portMap'] = mapping;
  if (!objects(d, 'instances').any((v) => v['deviceId'] == oldDevice))
    (d['devices'] as List).removeWhere((v) => v['id'] == oldDevice);
}

String pinArticleSymbol(Json d, Json article) {
  final original = cloneJson(
    validateSymbol(article['layers']?['symbol']?['definition']),
  );
  final existing = (d['symbols'] as List? ?? []).cast<Json>().where(
    (v) =>
        v['source']?['articleId'] == article['id'] &&
        v['source']?['version'] == article['version'],
  );
  if (existing.isNotEmpty) return 'custom_${existing.first['id']}';
  original['id'] = newId();
  original['source'] = {
    'articleId': article['id'],
    'version': article['version'],
    'license': article['layers']['symbol']['license'],
    'origin': article['origin'],
  };
  (d.putIfAbsent('symbols', () => <Json>[]) as List).add(original);
  return 'custom_${original['id']}';
}

Json portRef(String instanceId, String terminalId) => {
  'kind': 'port',
  'instanceId': instanceId,
  'terminalId': terminalId,
};
Json pointRef(String kind, String id) => {'kind': kind, 'id': id};

/// Visual port positions are derived from each view; electrical identity is
/// device + terminal, so multiple views never duplicate the physical terminal.
Point<double> endpointPosition(Json d, Json ref) {
  if (ref['kind'] == 'port') {
    final i = objectById(d, 'instances', ref['instanceId']);
    final ports = instancePorts(d, i), index = ports.indexOf(ref['terminalId']);
    if (index < 0) throw FormatException('Anschluss fehlt in der Darstellung.');
    final pin = symbolPins(symbolByKey(i['symbol'], d))[index];
    return Point(
      (i['x'] as num).toDouble() + (pin['x'] as num).toDouble(),
      (i['y'] as num).toDouble() + (pin['y'] as num).toDouble(),
    );
  }
  final o = objectById(
    d,
    ref['kind'] == 'node' ? 'nodes' : 'continuations',
    ref['id'],
  );
  return Point((o['x'] as num).toDouble(), (o['y'] as num).toDouble());
}

String endpointKey(Json d, Json ref) {
  if (ref['kind'] == 'port') {
    final i = objectById(d, 'instances', ref['instanceId']);
    return 'port:${i['deviceId']}:${ref['terminalId']}';
  }
  if (ref['kind'] == 'continuation') {
    final c = objectById(d, 'continuations', ref['id']);
    return 'continuation:${c['linkId']}';
  }
  return 'node:${ref['id']}';
}

/// Connectivity depends solely on explicit endpoint identities. Geometry and
/// identical labels never create connectivity. Net IDs derive from stable pins.
List<Json> nets(Json d) {
  final parent = <String, String>{};
  String root(String k) {
    parent.putIfAbsent(k, () => k);
    if (parent[k] != k) parent[k] = root(parent[k]!);
    return parent[k]!;
  }

  for (final i in objects(d, 'instances')) {
    for (final p in instancePorts(d, i)) {
      root(endpointKey(d, portRef(i['id'], p)));
    }
  }
  for (final kind in ['nodes', 'continuations']) {
    for (final o in objects(d, kind)) {
      root(
        endpointKey(
          d,
          pointRef(kind == 'nodes' ? 'node' : 'continuation', o['id']),
        ),
      );
    }
  }
  for (final wire in objects(d, 'wires')) {
    final a = root(endpointKey(d, wire['from'])),
        b = root(endpointKey(d, wire['to']));
    if (a != b) parent[b] = a;
  }
  final groups = <String, List<String>>{};
  for (final k in parent.keys.toList()) {
    groups.putIfAbsent(root(k), () => []).add(k);
  }
  return groups.values.map((members) {
    members.sort();
    final wires =
        objects(d, 'wires')
            .where((w) => members.contains(endpointKey(d, w['from'])))
            .map((w) => w['id'])
            .toList()
          ..sort();
    return <String, dynamic>{
      'id': members.first,
      'endpoints': members,
      'wireIds': wires,
      'connected': wires.isNotEmpty,
    };
  }).toList()..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
}

List<Json> crossReferences(Json d, String deviceId) => [
  for (final i in objects(
    d,
    'instances',
  ).where((i) => i['deviceId'] == deviceId))
    {
      'instanceId': i['id'],
      'sheetId': i['sheetId'],
      'position': positionReference(d, i),
      'symbol': i['symbol'],
    },
];

/// Strict input validation, including unknown keys, limits, references and BMKs.
/// Returns an independent copy; no caller-owned data is mutated.
Json validateDrawing(Object? input) {
  Never fail(String message) => throw FormatException(message);
  Json map(Object? v, Set<String> keys) {
    if (v is! Json || v.keys.any((k) => !keys.contains(k)))
      fail('Ungültige Objektfelder.');
    return v;
  }

  String text(Json v, String k, {int max = 160}) {
    final s = v[k];
    if (s is! String ||
        s.trim().isEmpty ||
        s.length > max ||
        s.contains(RegExp(r'[\x00-\x1f]')))
      fail('$k: gültiger Text erforderlich.');
    return s;
  }

  void id(Json v, String k) {
    final s = text(v, k, max: 80);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s)) fail('$k: ungültige ID.');
  }

  List<Json> list(Json v, String k, int max, Set<String> keys) {
    final l = v[k];
    if (l is! List || l.length > max)
      fail('$k: Liste mit höchstens $max Einträgen erforderlich.');
    final seen = <String>{};
    return l.map((e) {
      final o = map(e, keys);
      id(o, 'id');
      if (!seen.add(o['id'])) fail('$k: doppelte ID.');
      return o;
    }).toList();
  }

  void position(Json o) {
    for (final k in ['x', 'y']) {
      final n = o[k];
      if (n is! num ||
          !n.isFinite ||
          n % 20 != 0 ||
          n < (k == 'x' ? 80 : 100) ||
          n > (k == 'x' ? 1120 : 660))
        fail('$k: Position außerhalb des 20er-Rasters.');
    }
  }

  final d = map(input, {
    'schemaVersion',
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
  });
  if (d['schemaVersion'] != 1) fail('Unbekannte Zeichnungsversion.');
  if (d.containsKey('symbols')) {
    final raw = d['symbols'];
    if (raw is! List || raw.length > 100) fail('Maximal 100 Artikelsymbole.');
    final ids = <String>{};
    for (final v in raw) {
      final sym = validateSymbol(v);
      if (!ids.add(sym['id'])) fail('Doppelte Symbol-ID.');
    }
  }
  final sheets = list(d, 'sheets', 50, {'id', 'number', 'title'});
  if (sheets.isEmpty) fail('Mindestens ein Blatt erforderlich.');
  final sheetIds = sheets.map((s) => s['id']).toSet(), numbers = <int>{};
  for (final s in sheets) {
    final n = s['number'];
    if (n is! int || n < 1 || n > 9999 || !numbers.add(n))
      fail('Blattnummer fehlt oder ist doppelt.');
    text(s, 'title');
  }
  final devices = list(d, 'devices', 500, {
    'id',
    'bmk',
    'label',
    'type',
    'terminals',
    'article',
    'channels',
  });
  final bmks = <String>{};
  for (final o in devices) {
    final bmk = text(o, 'bmk', max: 80);
    if (bmk != bmk.trim() || !bmks.add(bmk.toUpperCase()))
      fail('BMK ist doppelt oder enthält Rand-Leerzeichen: $bmk');
    text(o, 'label');
    final type = text(o, 'type');
    final defs = drawingSymbols(d).where((s) => s.deviceType == type);
    if (defs.isEmpty) fail('Unbekannter Gerätetyp.');
    final terminals = list(o, 'terminals', 128, {'id', 'label'});
    for (final t in terminals) {
      text(t, 'label', max: 40);
    }
    final required = defs.first.allPorts.toSet();
    if (type == 'relay'
        ? !terminals.map((t) => t['id']).toSet().containsAll({'A1', 'A2'})
        : terminals.length != required.length ||
              !terminals.every((t) => required.contains(t['id'])))
      fail('Geräteanschlüsse passen nicht zum Typ.');
  }
  final instances = list(d, 'instances', 1000, {
    'id',
    'deviceId',
    'sheetId',
    'symbol',
    'portMap',
    'x',
    'y',
  });
  void onSheet(Json o) {
    if (!sheetIds.contains(o['sheetId'])) fail('Blattreferenz fehlt.');
    position(o);
  }

  for (final i in instances) {
    onSheet(i);
    final device = objectById(d, 'devices', text(i, 'deviceId'));
    if (symbolByKey(text(i, 'symbol'), d).deviceType != device['type'])
      fail('Symbol passt nicht zum Gerät.');
    final symbol = symbolByKey(i['symbol'], d), mapping = i['portMap'];
    if (mapping != null &&
        (mapping is! Json ||
            !symbol.isContact ||
            mapping.length != symbol.ports.length ||
            !mapping.keys.every(symbol.ports.contains) ||
            mapping.values.any((p) => p is! String) ||
            mapping.values.toSet().length != mapping.length))
      fail('Ungültige Kontaktanschluss-Zuordnung.');
    final ports = instancePorts(d, i),
        terminals = (device['terminals'] as List).map((t) => t['id']).toSet();
    if (!ports.every(terminals.contains))
      fail('Symbolanschluss fehlt am Gerät.');
    if (symbol.isContact && mapping != null) {
      final suffix = symbol.role == 'no' ? ['3', '4'] : ['1', '2'];
      final first =
          mapping['${symbol.role == 'no' ? 1 : 2}${suffix[0]}'] as String;
      final last =
          mapping['${symbol.role == 'no' ? 1 : 2}${suffix[1]}'] as String;
      if (!RegExp(r'^[1-9][0-9]*[1-4]$').hasMatch(first) ||
          first.substring(0, first.length - 1) !=
              last.substring(0, last.length - 1) ||
          !first.endsWith(suffix[0]) ||
          !last.endsWith(suffix[1]))
        fail('Kontaktart und Anschlussbelegung widersprechen sich.');
    }
  }
  final contactPins = <String, bool>{};
  for (final i in instances.where(
    (i) => symbolByKey(i['symbol'], d).isContact,
  )) {
    for (final p in instancePorts(d, i)) {
      final key = '${i['deviceId']}:$p';
      if (contactPins.containsKey(key) &&
          (contactPins[key]! || i['portMap'] != null))
        fail('Kontaktanschluss bereits einem anderen Kontakt zugeordnet.');
      contactPins[key] = i['portMap'] != null;
    }
  }
  for (final n in list(d, 'nodes', 1000, {'id', 'sheetId', 'x', 'y'})) {
    onSheet(n);
  }
  final links = <String, List<Json>>{};
  for (final c in list(d, 'continuations', 500, {
    'id',
    'sheetId',
    'x',
    'y',
    'linkId',
    'label',
  })) {
    onSheet(c);
    id(c, 'linkId');
    text(c, 'label');
    links.putIfAbsent(c['linkId'], () => []).add(c);
  }
  for (final pair in links.values) {
    if (pair.length != 2 || pair[0]['sheetId'] == pair[1]['sheetId'])
      fail(
        'Blattfortsetzung benötigt genau zwei Enden auf verschiedenen Blättern.',
      );
    if (pair[0]['label'] != pair[1]['label'])
      fail('Fortsetzungsbeschriftung muss übereinstimmen.');
  }
  final cables = list(d, 'cables', 500, {'id', 'bmk', 'cores'});
  for (final cable in cables) {
    final bmk = text(cable, 'bmk', max: 80);
    if (bmk != bmk.trim() || !bmks.add(bmk.toUpperCase()))
      fail('Kabel-BMK doppelt.');
    final cores = list(cable, 'cores', 100, {'id', 'label', 'color'});
    if (cores.isEmpty) fail('Kabel braucht mindestens eine Ader.');
    final labels = <String>{};
    for (final c in cores) {
      if (!labels.add(text(c, 'label', max: 40)))
        fail('Aderbezeichnung doppelt.');
      text(c, 'color', max: 40);
    }
  }
  String endpoint(Json ref, String sheetId) {
    final kind = ref['kind'];
    if (kind == 'port') {
      map(ref, {'kind', 'instanceId', 'terminalId'});
      final i = objectById(d, 'instances', text(ref, 'instanceId'));
      if (i['sheetId'] != sheetId ||
          !instancePorts(d, i).contains(ref['terminalId']))
        fail('Anschlussreferenz ungültig oder auf anderem Blatt.');
    } else if (kind == 'node' || kind == 'continuation') {
      map(ref, {'kind', 'id'});
      final o = objectById(
        d,
        kind == 'node' ? 'nodes' : 'continuations',
        text(ref, 'id'),
      );
      if (o['sheetId'] != sheetId)
        fail('Endpunkt auf anderem Blatt; Fortsetzung verwenden.');
    } else {
      fail('Unbekannter Endpunkttyp.');
    }
    return endpointKey(d, ref);
  }

  final usedCores = <String>{}, edges = <String>{};
  for (final w in list(d, 'wires', 2000, {
    'id',
    'sheetId',
    'from',
    'to',
    'cableId',
    'coreId',
    'conductor',
  })) {
    if (w['conductor'] != null &&
        !{'L1', 'L2', 'L3', 'N', 'PE'}.contains(w['conductor']))
      fail('Unbekannter Leiter.');
    final sheet = text(w, 'sheetId');
    if (!sheetIds.contains(sheet)) fail('Leitungsblatt fehlt.');
    final from = w['from'], to = w['to'];
    if (from is! Json || to is! Json) fail('Leitungsendpunkt fehlt.');
    final a = endpoint(from, sheet), b = endpoint(to, sheet);
    if (a == b) fail('Verbindung zum selben elektrischen Anschluss.');
    final edge = [a, b]..sort();
    if (!edges.add('$sheet:${edge.join('|')}')) fail('Doppelte Verbindung.');
    if (w['cableId'] != null || w['coreId'] != null) {
      final cable = objectById(d, 'cables', text(w, 'cableId'));
      final core = text(w, 'coreId');
      if (!(cable['cores'] as List).any((c) => c['id'] == core))
        fail('Kabelader fehlt.');
      if (!usedCores.add('${cable['id']}:$core'))
        fail('Kabelader mehrfach belegt.');
    }
  }
  validatePlanning(d);
  validateCalculations(d);
  return cloneJson(d);
}
