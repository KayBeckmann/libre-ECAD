/// Original synthetic teaching glyphs, covered by the repository MIT license.
/// No standards database or manufacturer symbol is embedded.
class SymbolDefinition {
  const SymbolDefinition(
    this.key,
    this.name,
    this.group,
    this.deviceType,
    this.code,
    this.ports,
    this.allPorts, {
    this.definition,
  });
  final String key, name, group, deviceType, code;
  final List<String> ports, allPorts;
  final Map<String, dynamic>? definition;
  String get role =>
      definition?['role'] ??
      switch (key) {
        'coil' => 'coil',
        'contact' => 'no',
        'contact_nc' => 'nc',
        _ => 'generic',
      };
  bool get isContact => role == 'no' || role == 'nc';
}

const symbolLibrary = <SymbolDefinition>[
  SymbolDefinition(
    'supply',
    'Einspeisung',
    'Verteilerabgang',
    'supply',
    'G',
    ['L', 'N'],
    ['L', 'N'],
  ),
  SymbolDefinition(
    'breaker',
    'Schutzgerät',
    'Verteilerabgang',
    'breaker',
    'Q',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'terminal',
    'Klemme',
    'Verteilerabgang',
    'terminal',
    'X',
    ['1'],
    ['1'],
  ),
  SymbolDefinition(
    'switch',
    'Schalter',
    'Steuer- / Motorabgang',
    'switch',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'coil',
    'Relaisspule',
    'Steuer- / Motorabgang',
    'relay',
    'K',
    ['A1', 'A2'],
    ['A1', 'A2', '13', '14'],
  ),
  SymbolDefinition(
    'contact',
    'Relaiskontakt · Schließer',
    'Steuer- / Motorabgang',
    'relay',
    'K',
    ['13', '14'],
    ['A1', 'A2', '13', '14'],
  ),
  SymbolDefinition(
    'motor',
    'Motor',
    'Steuer- / Motorabgang',
    'motor',
    'M',
    ['U', 'V', 'W', 'PE'],
    ['U', 'V', 'W', 'PE'],
  ),
  SymbolDefinition(
    'contact_nc',
    'Relaiskontakt · Öffner',
    'Steuer- / Motorabgang',
    'relay',
    'K',
    ['21', '22'],
    ['A1', 'A2', '21', '22'],
  ),
  SymbolDefinition(
    'supply3',
    'Einspeisung · L1 L2 L3 N PE',
    'Drehstrom',
    'supply3',
    'G',
    ['L1', 'L2', 'L3', 'N', 'PE'],
    ['L1', 'L2', 'L3', 'N', 'PE'],
  ),
  SymbolDefinition(
    'breaker3',
    'Schutzgerät · dreipolig',
    'Drehstrom',
    'breaker3',
    'Q',
    ['1', '3', '5', '2', '4', '6'],
    ['1', '3', '5', '2', '4', '6'],
  ),
];

Iterable<SymbolDefinition> drawingSymbols(Map<String, dynamic> d) sync* {
  yield* symbolLibrary;
  for (final raw in (d['symbols'] as List? ?? [])) {
    final v = raw as Map<String, dynamic>;
    final ports = (v['ports'] as List).map((p) => p['id'] as String).toList();
    yield SymbolDefinition(
      'custom_${v['id']}',
      v['name'],
      'Artikelsymbole',
      v['role'] == 'generic' ? 'custom_${v['id']}' : 'relay',
      v['code'],
      ports,
      v['role'] == 'generic' ? ports : {...ports, 'A1', 'A2'}.toList(),
      definition: v,
    );
  }
}

SymbolDefinition symbolByKey(String key, [Map<String, dynamic>? drawing]) =>
    (drawing == null ? symbolLibrary : drawingSymbols(drawing)).firstWhere(
      (s) => s.key == key,
      orElse: () => throw FormatException('Unbekanntes Symbol: $key'),
    );

/// Safe vector data, never executable SVG, URLs or embedded fonts.
Map<String, dynamic> validateSymbol(Object? input) {
  Never fail() => throw FormatException(
    'Ungültiges Schaltsymbol: Raster, Geometrie, Anschluss-IDs oder Funktion prüfen.',
  );
  if (input is! Map<String, dynamic> ||
      input.keys.any(
        (k) => !{
          'id',
          'name',
          'code',
          'role',
          'ports',
          'primitives',
          'source',
        }.contains(k),
      ))
    fail();
  for (final key in ['id', 'name', 'code', 'role']) {
    if (input[key] is! String ||
        (input[key] as String).isEmpty ||
        (input[key] as String).length > 100)
      fail();
  }
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(input['id']) ||
      !RegExp(r'^[A-Z]{1,4}$').hasMatch(input['code']) ||
      !{'generic', 'coil', 'no', 'nc'}.contains(input['role']))
    fail();
  num coord(dynamic n) {
    if (n is! num || !n.isFinite || n < -120 || n > 120 || n % 10 != 0) fail();
    return n;
  }

  final ports = input['ports'];
  if (ports is! List || ports.isEmpty || ports.length > 32) fail();
  final ids = <String>{}, positions = <String>{};
  for (final p in ports) {
    if (p is! Map<String, dynamic> ||
        p.keys.any((k) => !{'id', 'label', 'x', 'y'}.contains(k)))
      fail();
    if (p['id'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(p['id']) ||
        !ids.add(p['id']) ||
        p['label'] is! String ||
        (p['label'] as String).trim().isEmpty ||
        (p['label'] as String).length > 40)
      fail();
    coord(p['x']);
    coord(p['y']);
    if (!positions.add('${p['x']}/${p['y']}')) fail();
  }
  final expected = switch (input['role']) {
    'coil' => {'A1', 'A2'},
    'no' => {'13', '14'},
    'nc' => {'21', '22'},
    _ => ids,
  };
  if (ids.length != expected.length || !ids.containsAll(expected)) fail();
  if (input['role'] != 'generic' && input['code'] != 'K') fail();
  final shapes = input['primitives'];
  if (shapes is! List || shapes.isEmpty || shapes.length > 128) fail();
  for (final p in shapes) {
    if (p is! Map<String, dynamic>) fail();
    final fields = switch (p['kind']) {
      'line' => {'kind', 'x', 'y', 'x2', 'y2'},
      'rect' => {'kind', 'x', 'y', 'x2', 'y2'},
      'circle' => {'kind', 'x', 'y', 'radius'},
      'text' => {'kind', 'x', 'y', 'text'},
      _ => <String>{},
    };
    if (fields.isEmpty ||
        p.keys.toSet().difference(fields).isNotEmpty ||
        !p.keys.toSet().containsAll(fields))
      fail();
    coord(p['x']);
    coord(p['y']);
    if (p['kind'] == 'line' || p['kind'] == 'rect') {
      coord(p['x2']);
      coord(p['y2']);
      if (p['x'] == p['x2'] && p['y'] == p['y2']) fail();
      if (p['kind'] == 'rect' && (p['x'] == p['x2'] || p['y'] == p['y2']))
        fail();
    }
    if (p['kind'] == 'circle') {
      final r = coord(p['radius']);
      if (r <= 0 ||
          (p['x'] as num).abs() + r > 120 ||
          (p['y'] as num).abs() + r > 120)
        fail();
    }
    if (p['kind'] == 'text' &&
        (p['text'] is! String ||
            (p['text'] as String).trim().isEmpty ||
            (p['text'] as String).length > 40 ||
            (p['text'] as String).contains(RegExp(r'[\x00-\x1f]'))))
      fail();
  }
  final source = input['source'];
  if (source != null &&
      (source is! Map<String, dynamic> ||
          source.keys.any(
            (k) => !{'articleId', 'version', 'license', 'origin'}.contains(k),
          ) ||
          source['articleId'] is! String ||
          (source['articleId'] as String).length > 100 ||
          source['version'] is! int ||
          source['version'] < 1 ||
          source['license'] is! String ||
          (source['license'] as String).length > 2000 ||
          source['origin'] is! String ||
          (source['origin'] as String).length > 2000))
    fail();
  return input;
}

List<Map<String, dynamic>> symbolPins(SymbolDefinition s) {
  if (s.definition != null)
    return (s.definition!['ports'] as List).cast<Map<String, dynamic>>();
  return [
    for (var index = 0; index < s.ports.length; index++)
      {
        'id': s.ports[index],
        'label': s.ports[index],
        'x': s.key == 'breaker3'
            ? (index % 3 - 1) * 40
            : s.key == 'supply3'
            ? (index - 2) * 40
            : s.ports.length <= 2
            ? 0
            : -60 + index * 40,
        'y': s.key == 'breaker3'
            ? (index < 3 ? -40 : 40)
            : s.key == 'supply3'
            ? 40
            : s.ports.length == 1
            ? 0
            : s.ports.length == 2
            ? (index == 0 ? -40 : 40)
            : -40,
      },
  ];
}

List<Map<String, dynamic>> symbolGeometry(SymbolDefinition s) {
  if (s.definition != null)
    return (s.definition!['primitives'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> line(num x, num y, num x2, num y2) => {
    'kind': 'line',
    'x': x,
    'y': y,
    'x2': x2,
    'y2': y2,
  };
  Map<String, dynamic> rect(num x, num y, num x2, num y2) => {
    'kind': 'rect',
    'x': x,
    'y': y,
    'x2': x2,
    'y2': y2,
  };
  Map<String, dynamic> circle(num x, num y, num r) => {
    'kind': 'circle',
    'x': x,
    'y': y,
    'radius': r,
  };
  Map<String, dynamic> text(String t, num x, num y) => {
    'kind': 'text',
    'x': x,
    'y': y,
    'text': t,
  };
  if (s.key == 'terminal') return [circle(0, 0, 8), line(-5, 0, 5, 0)];
  if (s.key == 'motor')
    return [
      circle(0, 0, 24),
      text('M', -8, -10),
      text('3~', -10, 8),
      for (final p in symbolPins(s)) line(p['x'], p['y'], p['x'], -24),
    ];
  if (s.key == 'supply3')
    return [
      rect(-100, -20, 100, 20),
      text('3~', -10, -10),
      for (final p in symbolPins(s)) line(p['x'], 20, p['x'], 40),
    ];
  if (s.key == 'breaker3')
    return [
      for (final x in [-40, 0, 40]) ...[
        line(x, -40, x, -20),
        rect(x - 10, -20, x + 10, 20),
        line(x, 20, x, 40),
      ],
      for (var x = -40; x < 40; x += 10) line(x, 0, x + 4, 0),
    ];
  return [
    line(0, -40, 0, -18),
    line(0, 18, 0, 40),
    if (s.key == 'switch' || s.isContact) ...[
      line(0, 18, s.role == 'nc' ? 0 : 20, -18),
      circle(0, -18, 2),
      circle(0, 18, 2),
      if (s.role == 'nc') line(-10, -18, 10, -18),
    ] else ...[
      rect(-22, -18, 22, 18),
      text(s.code, -7, -9),
    ],
  ];
}

Map<String, dynamic> symbolTemplate(String key, String id) {
  final s = symbolByKey(key);
  num snap(num n) => (n / 10).round() * 10;
  return {
    'id': id,
    'name': s.name,
    'code': s.code,
    'role': s.role,
    'ports': [
      for (final p in symbolPins(s))
        {...p, 'x': snap(p['x']), 'y': snap(p['y'])},
    ],
    'primitives': [
      for (final shape in symbolGeometry(s))
        if (!(shape['kind'] == 'line' &&
            snap(shape['x']) == snap(shape['x2']) &&
            snap(shape['y']) == snap(shape['y2'])))
          {
            for (final e in shape.entries)
              e.key: e.key == 'radius' && snap(e.value) < 10
                  ? 10
                  : e.value is num
                  ? snap(e.value)
                  : e.value,
          },
    ],
  };
}
