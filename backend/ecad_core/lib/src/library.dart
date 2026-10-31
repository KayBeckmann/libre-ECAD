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
  SymbolDefinition(
    'plc',
    'SPS · I/O-Modul',
    'Automatisierung',
    'plc',
    'A',
    ['V', 'M', 'I0', 'I1', 'Q0', 'Q1', 'COM', 'ETH'],
    ['V', 'M', 'I0', 'I1', 'Q0', 'Q1', 'COM', 'ETH'],
  ),
  SymbolDefinition(
    'drive',
    'Frequenzumrichter · Block',
    'Automatisierung',
    'drive',
    'T',
    [
      'L1',
      'L2',
      'L3',
      'PE',
      'DI1',
      'DI2',
      'U',
      'V',
      'W',
      'PE_OUT',
      'DO1',
      'ETH',
    ],
    [
      'L1',
      'L2',
      'L3',
      'PE',
      'DI1',
      'DI2',
      'U',
      'V',
      'W',
      'PE_OUT',
      'DO1',
      'ETH',
    ],
  ),
  SymbolDefinition(
    'safety',
    'Sicherheitsmodul · Block',
    'Automatisierung',
    'safety',
    'K',
    ['A1', 'A2', 'S11', 'S12', 'S21', 'S22', '13', '14'],
    ['A1', 'A2', 'S11', 'S12', 'S21', 'S22', '13', '14'],
  ),
  // Original teaching glyphs, not copies of manufacturer or IEC artwork.
  SymbolDefinition(
    'earth',
    'Schutzleiter / Erde',
    'Grundschaltungen',
    'earth',
    'X',
    ['PE'],
    ['PE'],
  ),
  SymbolDefinition(
    'fuse',
    'Sicherung',
    'Grundschaltungen',
    'fuse',
    'F',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'resistor',
    'Widerstand',
    'Grundschaltungen',
    'resistor',
    'R',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'capacitor',
    'Kondensator',
    'Grundschaltungen',
    'capacitor',
    'C',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'diode',
    'Diode',
    'Grundschaltungen',
    'diode',
    'V',
    ['A', 'K'],
    ['A', 'K'],
  ),
  SymbolDefinition(
    'led',
    'Leuchtdiode',
    'Grundschaltungen',
    'led',
    'V',
    ['A', 'K'],
    ['A', 'K'],
  ),
  SymbolDefinition(
    'battery',
    'Batterie',
    'Grundschaltungen',
    'battery',
    'G',
    ['P', 'N'],
    ['P', 'N'],
  ),
  SymbolDefinition(
    'transformer',
    'Transformator',
    'Grundschaltungen',
    'transformer',
    'T',
    ['P1', 'P2', 'S1', 'S2'],
    ['P1', 'P2', 'S1', 'S2'],
  ),
  SymbolDefinition(
    'lamp',
    'Lampe',
    'Grundschaltungen',
    'lamp',
    'H',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'push_no',
    'Taster · Schließer',
    'Grundschaltungen',
    'push_no',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'push_nc',
    'Taster · Öffner',
    'Grundschaltungen',
    'push_nc',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'changeover',
    'Umschalter',
    'Grundschaltungen',
    'changeover',
    'S',
    ['COM', 'NO', 'NC'],
    ['COM', 'NO', 'NC'],
  ),
  SymbolDefinition(
    'buzzer',
    'Summer / Hupe',
    'Grundschaltungen',
    'buzzer',
    'H',
    ['P', 'N'],
    ['P', 'N'],
  ),
  SymbolDefinition(
    'voltmeter',
    'Voltmeter',
    'Grundschaltungen',
    'voltmeter',
    'P',
    ['P', 'N'],
    ['P', 'N'],
  ),
  SymbolDefinition(
    'ammeter',
    'Amperemeter',
    'Grundschaltungen',
    'ammeter',
    'P',
    ['P', 'N'],
    ['P', 'N'],
  ),
  SymbolDefinition(
    'solar_cell',
    'Photovoltaikzelle',
    'Grundschaltungen',
    'solar_cell',
    'G',
    ['P', 'N'],
    ['P', 'N'],
  ),
  // Keep the historical first 29 IDs in order for version-4 pinned drawings.
  SymbolDefinition(
    'key_switch_no',
    'Schlüsselschalter · Schließer',
    'Grundschaltungen',
    'key_switch_no',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'key_switch_nc',
    'Schlüsselschalter · Öffner',
    'Grundschaltungen',
    'key_switch_nc',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'stage_switch_3pos',
    'Stufenschalter 0/1/2',
    'Grundschaltungen',
    'stage_switch_3pos',
    'S',
    ['COM', 'S1', 'S2'],
    ['COM', 'S1', 'S2'],
  ),
  SymbolDefinition(
    'selector_3pos',
    'Wahlschalter 1/2/3',
    'Grundschaltungen',
    'selector_3pos',
    'S',
    ['COM', 'P1', 'P2', 'P3'],
    ['COM', 'P1', 'P2', 'P3'],
  ),
  // Independently drafted functional glyphs, not external artwork.
  SymbolDefinition(
    'mcb1',
    'Leitungsschutzschalter 1-polig',
    'Schutzgeräte',
    'mcb1',
    'Q',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'mcb2',
    'Leitungsschutzschalter 2-polig',
    'Schutzgeräte',
    'mcb2',
    'Q',
    ['1', '3', '2', '4'],
    ['1', '3', '2', '4'],
  ),
  SymbolDefinition(
    'mcb3',
    'Leitungsschutzschalter 3-polig',
    'Schutzgeräte',
    'mcb3',
    'Q',
    ['1', '3', '5', '2', '4', '6'],
    ['1', '3', '5', '2', '4', '6'],
  ),
  SymbolDefinition(
    'rcd2',
    'FI/RCD 2-polig',
    'Schutzgeräte',
    'rcd2',
    'Q',
    ['1', '3', '2', '4'],
    ['1', '3', '2', '4'],
  ),
  SymbolDefinition(
    'rcd4',
    'FI/RCD 4-polig',
    'Schutzgeräte',
    'rcd4',
    'Q',
    ['1', '3', '5', '7', '2', '4', '6', '8'],
    ['1', '3', '5', '7', '2', '4', '6', '8'],
  ),
  SymbolDefinition(
    'rcbo2',
    'FI/LS 2-polig',
    'Schutzgeräte',
    'rcbo2',
    'Q',
    ['1', '3', '2', '4'],
    ['1', '3', '2', '4'],
  ),
  SymbolDefinition(
    'rcbo4',
    'FI/LS 4-polig',
    'Schutzgeräte',
    'rcbo4',
    'Q',
    ['1', '3', '5', '7', '2', '4', '6', '8'],
    ['1', '3', '5', '7', '2', '4', '6', '8'],
  ),
  SymbolDefinition(
    'motor_protection',
    'Motorschutzschalter',
    'Schutzgeräte',
    'motor_protection',
    'Q',
    ['1', '3', '5', '2', '4', '6'],
    ['1', '3', '5', '2', '4', '6'],
  ),
  SymbolDefinition(
    'motor_dc',
    'Gleichstrommotor',
    'Antriebe / Energie',
    'motor_dc',
    'M',
    ['P', 'N'],
    ['P', 'N'],
  ),
  SymbolDefinition(
    'motor_1ph',
    'Wechselstrommotor 1-phasig',
    'Antriebe / Energie',
    'motor_1ph',
    'M',
    ['L', 'N', 'PE'],
    ['L', 'N', 'PE'],
  ),
  SymbolDefinition(
    'motor_1ph_thermistor',
    'Wechselstrommotor 1~ mit Thermistor T1/T2',
    'Antriebe / Energie',
    'motor_1ph_thermistor',
    'M',
    ['L', 'N', 'PE', 'T1', 'T2'],
    ['L', 'N', 'PE', 'T1', 'T2'],
  ),
  SymbolDefinition(
    'motor_3ph_thermistor',
    'Drehstrommotor 3~ mit Thermistor T1/T2',
    'Antriebe / Energie',
    'motor_3ph_thermistor',
    'M',
    ['U', 'V', 'W', 'PE', 'T1', 'T2'],
    ['U', 'V', 'W', 'PE', 'T1', 'T2'],
  ),
  SymbolDefinition(
    'motor_6terminal',
    'Drehstrommotor 6 Klemmen',
    'Antriebe / Energie',
    'motor_6terminal',
    'M',
    ['U1', 'V1', 'W1', 'U2', 'V2', 'W2'],
    ['U1', 'V1', 'W1', 'U2', 'V2', 'W2'],
  ),
  SymbolDefinition(
    'converter_ac_ac',
    'Umformer AC/AC',
    'Antriebe / Energie',
    'converter_ac_ac',
    'T',
    ['L', 'N', 'OUT_L', 'OUT_N'],
    ['L', 'N', 'OUT_L', 'OUT_N'],
  ),
  SymbolDefinition(
    'converter_ac_dc',
    'Umformer AC/DC',
    'Antriebe / Energie',
    'converter_ac_dc',
    'T',
    ['L', 'N', 'P', 'M'],
    ['L', 'N', 'P', 'M'],
  ),
  SymbolDefinition(
    'psu_pe',
    'Netzteil AC/DC mit PE',
    'Antriebe / Energie',
    'psu_pe',
    'G',
    ['L', 'N', 'PE', 'P', 'M'],
    ['L', 'N', 'PE', 'P', 'M'],
  ),
  SymbolDefinition(
    'heater',
    'Heizwiderstand',
    'Antriebe / Energie',
    'heater',
    'R',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'potentiometer',
    'Potentiometer',
    'Elektronik',
    'potentiometer',
    'R',
    ['1', '2', 'W'],
    ['1', '2', 'W'],
  ),
  SymbolDefinition(
    'ldr',
    'Fotowiderstand LDR',
    'Elektronik',
    'ldr',
    'R',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'transistor_npn',
    'Transistor NPN',
    'Elektronik',
    'transistor_npn',
    'V',
    ['C', 'B', 'E'],
    ['C', 'B', 'E'],
  ),
  SymbolDefinition(
    'transistor_pnp',
    'Transistor PNP',
    'Elektronik',
    'transistor_pnp',
    'V',
    ['C', 'B', 'E'],
    ['C', 'B', 'E'],
  ),
  SymbolDefinition(
    'triac',
    'TRIAC',
    'Elektronik',
    'triac',
    'V',
    ['MT1', 'MT2', 'G'],
    ['MT1', 'MT2', 'G'],
  ),
  SymbolDefinition(
    'diac',
    'DIAC',
    'Elektronik',
    'diac',
    'V',
    ['A1', 'A2'],
    ['A1', 'A2'],
  ),
  SymbolDefinition(
    'ic4',
    'IC 4 Pins',
    'Elektronik',
    'ic4',
    'A',
    ['1', '2', '3', '4'],
    ['1', '2', '3', '4'],
  ),
  SymbolDefinition(
    'ic6',
    'IC 6 Pins',
    'Elektronik',
    'ic6',
    'A',
    ['1', '2', '3', '4', '5', '6'],
    ['1', '2', '3', '4', '5', '6'],
  ),
  SymbolDefinition(
    'ic8',
    'IC 8 Pins',
    'Elektronik',
    'ic8',
    'A',
    ['1', '2', '3', '4', '5', '6', '7', '8'],
    ['1', '2', '3', '4', '5', '6', '7', '8'],
  ),
  SymbolDefinition(
    'ic10',
    'IC 10 Pins',
    'Elektronik',
    'ic10',
    'A',
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
  ),
  SymbolDefinition(
    'pcb_terminal2',
    'Printklemme 2-polig',
    'Anschlussklemmen',
    'pcb_terminal2',
    'X',
    ['1', '2'],
    ['1', '2'],
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
      final r = p['radius'];
      // Radii need finer resolution than the ten-unit placement grid.
      if (r is! num ||
          !r.isFinite ||
          r <= 0 ||
          r % 1 != 0 ||
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
  if (const {
    'Schutzgeräte',
    'Antriebe / Energie',
    'Elektronik',
    'Anschlussklemmen',
  }.contains(s.group)) {
    final count = s.ports.length, half = count ~/ 2;
    final pins = <(int, int)>[];
    if (s.group == 'Schutzgeräte' || s.key == 'motor_6terminal') {
      for (var i = 0; i < count; i++) {
        pins.add(((i % half) * 40 - (half - 1) * 20, i < half ? -60 : 60));
      }
    } else if (s.key.startsWith('ic')) {
      for (var i = 0; i < count; i++) {
        pins.add((i < half ? -60 : 60, (i % half) * 40 - (half - 1) * 20));
      }
    } else if (s.key == 'psu_pe') {
      pins.addAll([(-60, -40), (-60, 0), (-60, 40), (60, -20), (60, 20)]);
    } else if (s.key.startsWith('converter_')) {
      pins.addAll([(-60, -20), (-60, 20), (60, -20), (60, 20)]);
    } else if (const {
      'transistor_npn',
      'transistor_pnp',
      'triac',
    }.contains(s.key)) {
      pins.addAll([(0, -60), (-60, 0), (0, 60)]);
    } else if (s.key == 'potentiometer') {
      pins.addAll([(0, -60), (0, 60), (60, 0)]);
    } else if (s.key == 'motor_1ph') {
      pins.addAll([(-40, -60), (40, -60), (0, 60)]);
    } else if (s.key == 'motor_1ph_thermistor') {
      pins.addAll([(-20, -60), (20, -60), (0, 60), (80, -20), (80, 20)]);
    } else if (s.key == 'motor_3ph_thermistor') {
      pins.addAll([
        (-20, -60),
        (0, -60),
        (20, -60),
        (0, 60),
        (80, -20),
        (80, 20),
      ]);
    } else {
      pins.addAll([(0, -60), (0, 60)]);
    }
    return [
      for (var i = 0; i < count; i++)
        {
          'id': s.ports[i],
          'label': s.ports[i],
          'x': pins[i].$1,
          'y': pins[i].$2,
        },
    ];
  }
  if (s.group == 'Grundschaltungen') {
    final positions = switch (s.key) {
      'earth' => [(0, -40)],
      'transformer' => [(-40, -40), (-40, 40), (40, -40), (40, 40)],
      'changeover' => [(-40, 0), (40, -40), (40, 40)],
      'stage_switch_3pos' => [(-60, 0), (60, -30), (60, 30)],
      'selector_3pos' => [(-60, 0), (60, -40), (60, 0), (60, 40)],
      _ => [(0, -40), (0, 40)],
    };
    return [
      for (var i = 0; i < s.ports.length; i++)
        {
          'id': s.ports[i],
          'label': switch (s.ports[i]) {
            'P' => '+',
            'N' => '−',
            _ => s.ports[i],
          },
          'x': positions[i].$1,
          'y': positions[i].$2,
        },
    ];
  }
  if (s.group == 'Automatisierung') {
    final half = s.ports.length ~/ 2;
    return [
      for (var n = 0; n < s.ports.length; n++)
        {
          'id': s.ports[n],
          'label': s.ports[n],
          'x': n < half ? -80 : 80,
          'y': (n % half) * 40 - (half - 1) * 20,
        },
    ];
  }
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
  if (s.group == 'Schutzgeräte') {
    final pins = symbolPins(s), columns = s.ports.length ~/ 2;
    final halfWidth = columns * 20;
    return [
      for (var i = 0; i < columns; i++) ...[
        line(pins[i]['x'], -60, pins[i]['x'], -20),
        line(pins[i]['x'], 20, pins[i]['x'], 60),
        circle(pins[i]['x'], -20, 4),
        circle(pins[i]['x'], 20, 4),
        // Resting open: the lower blade stops clear of the upper fixed node.
        line(pins[i]['x'], 20, (pins[i]['x'] as num) + 20, -10),
      ],
      // Dashes mark mechanical coupling, never an electrical connection.
      if (columns > 1)
        for (var i = 0; i < columns - 1; i++)
          line((pins[i]['x'] as num) + 20, 10, (pins[i]['x'] as num) + 30, 10),
      if (s.key.startsWith('rcd') || s.key.startsWith('rcbo'))
        text('IΔ', -halfWidth + 10, -40),
      if (s.key.startsWith('mcb') || s.key.startsWith('rcbo'))
        text('I>', halfWidth - 30, -40),
      if (s.key == 'motor_protection') text('M I>', -20, -40),
    ];
  }
  if (const {
    'Antriebe / Energie',
    'Elektronik',
    'Anschlussklemmen',
  }.contains(s.group)) {
    final pins = symbolPins(s);
    final stems = [
      for (final p in pins)
        if ((p['x'] as num).abs() == 60)
          line(p['x'], p['y'], (p['x'] as num) < 0 ? -40 : 40, p['y'])
        else if ((p['y'] as num).abs() == 60)
          line(p['x'], p['y'], p['x'], (p['y'] as num) < 0 ? -40 : 40),
    ];
    if (s.key == 'motor_1ph_thermistor' || s.key == 'motor_3ph_thermistor')
      return [
        for (final p in pins.where((p) => p['id'] != 'T1' && p['id'] != 'T2'))
          line(p['x'], p['y'], p['x'], (p['y'] as num) < 0 ? -30 : 30),
        circle(0, 0, 30),
        text('M', -10, -10),
        text(s.key == 'motor_1ph_thermistor' ? '1~' : '3~', -10, 10),
        // The thermal sensing circuit is drawn outside the motor outline.
        // Neither of its leads touches a winding or protective-earth lead.
        line(80, -20, 60, -20),
        line(60, -20, 60, -10),
        rect(50, -10, 70, 10),
        line(50, 10, 70, -10),
        line(60, 10, 60, 20),
        line(60, 20, 80, 20),
      ];
    if (s.key.startsWith('motor_'))
      return [
        ...stems,
        if (s.key == 'motor_6terminal' || s.key == 'motor_1ph')
          for (final p in pins.where(
            (p) => (p['y'] as num).abs() == 60 && p['x'] != 0,
          ))
            line(p['x'], (p['y'] as num) < 0 ? -40 : 40, p['x'], 0),
        circle(0, 0, 40),
        text('M', -10, -10),
        text(
          s.key == 'motor_dc'
              ? 'DC'
              : s.key == 'motor_1ph'
              ? '1~'
              : '3~',
          -10,
          10,
        ),
      ];
    if (s.key.startsWith('converter_') || s.key == 'psu_pe')
      return [
        ...stems,
        rect(-40, -50, 40, 50),
        text('~', -30, -10),
        line(-20, 20, 20, -20),
        text(s.key == 'converter_ac_ac' ? '~' : 'DC', 10, 10),
        if (s.key == 'psu_pe') text('PE', -30, 30),
      ];
    if (s.key.startsWith('ic'))
      return [
        ...stems,
        rect(
          -40,
          -((pins.length ~/ 2 - 1) * 20 + 10),
          40,
          (pins.length ~/ 2 - 1) * 20 + 10,
        ),
        text('IC', -10, -10),
      ];
    if (s.key == 'pcb_terminal2')
      return [
        ...stems,
        rect(-30, -40, 30, 40),
        circle(0, -20, 10),
        circle(0, 20, 10),
      ];
    if (s.key.startsWith('transistor_'))
      return [
        ...stems,
        circle(0, 0, 30),
        line(-40, 0, 0, 0),
        line(0, -20, 0, 20),
        line(0, -20, 0, -40),
        line(0, 20, 0, 40),
        if (s.key == 'transistor_npn') ...[
          line(0, 30, -10, 20),
          line(0, 30, 10, 20),
        ] else ...[
          line(0, 10, -10, 20),
          line(0, 10, 10, 20),
        ],
      ];
    if (s.key == 'triac' || s.key == 'diac')
      return [
        ...stems,
        line(-20, -20, 20, -20),
        line(-20, 20, 20, 20),
        line(-20, -20, 20, 20),
        line(20, -20, -20, 20),
        if (s.key == 'triac') line(-40, 0, -10, 10),
      ];
    if (const {'potentiometer', 'ldr', 'heater'}.contains(s.key))
      return [
        ...stems,
        rect(-20, -30, 20, 30),
        if (s.key == 'potentiometer') ...[
          line(60, 0, 20, 0),
          line(20, 0, 30, -10),
          line(20, 0, 30, 10),
        ],
        if (s.key == 'ldr') ...[
          line(-50, -40, -20, -10),
          line(-50, -20, -20, 10),
        ],
        if (s.key == 'heater') text('T', -10, -10),
      ];
  }
  if (s.group == 'Grundschaltungen') {
    final stem = [line(0, -40, 0, -20), line(0, 20, 0, 40)];
    return switch (s.key) {
      'earth' => [
        line(0, -40, 0, 0),
        line(-30, 0, 30, 0),
        line(-20, 10, 20, 10),
        line(-10, 20, 10, 20),
      ],
      'fuse' => [...stem, rect(-10, -20, 10, 20), line(-10, -20, 10, 20)],
      'resistor' => [...stem, rect(-20, -20, 20, 20)],
      'capacitor' => [
        line(0, -40, 0, -10),
        line(-30, -10, 30, -10),
        line(-30, 10, 30, 10),
        line(0, 10, 0, 40),
      ],
      'diode' || 'led' => [
        ...stem,
        line(-20, -20, 20, -20),
        line(-20, -20, 0, 20),
        line(20, -20, 0, 20),
        line(-20, 20, 20, 20),
        if (s.key == 'led') ...[
          line(20, -10, 40, -30),
          line(40, -30, 30, -30),
          line(40, -30, 40, -20),
          line(20, 10, 40, -10),
          line(40, -10, 30, -10),
          line(40, -10, 40, 0),
        ],
      ],
      'battery' => [
        line(0, -40, 0, -10),
        line(-30, -10, 30, -10),
        line(-20, 10, 20, 10),
        line(0, 10, 0, 40),
        text('+', 40, -20),
      ],
      'transformer' => [
        line(-40, -40, -40, -20),
        line(-40, 20, -40, 40),
        line(40, -40, 40, -20),
        line(40, 20, 40, 40),
        circle(-40, -10, 10),
        circle(-40, 10, 10),
        circle(40, -10, 10),
        circle(40, 10, 10),
        line(-10, -30, -10, 30),
        line(10, -30, 10, 30),
      ],
      'lamp' => [
        ...stem,
        circle(0, 0, 20),
        line(-10, -10, 10, 10),
        line(-10, 10, 10, -10),
      ],
      'push_no' || 'push_nc' => [
        ...stem,
        circle(0, -20, 4),
        circle(0, 20, 4),
        line(0, 20, s.key == 'push_nc' ? 0 : 20, -20),
        // Manual push actuator, not a third conductive pin.
        line(-30, -10, -10, -10),
        line(-20, -20, -20, 0),
      ],
      'changeover' => [
        line(-40, 0, -20, 0),
        line(-20, 0, 20, 40),
        line(20, -40, 40, -40),
        line(20, 40, 40, 40),
        circle(-20, 0, 10),
        circle(20, -40, 10),
        circle(20, 40, 10),
      ],
      'key_switch_no' || 'key_switch_nc' => [
        ...stem,
        circle(0, -20, 4),
        circle(0, 20, 4),
        line(0, 20, s.key == 'key_switch_nc' ? 0 : 20, -20),
        // Key/actuator mark is not an additional electrical terminal.
        line(-30, -10, -10, -10),
        circle(-30, -10, 8),
      ],
      'stage_switch_3pos' || 'selector_3pos' => [
        line(-60, 0, -40, 0),
        circle(-40, 0, 4),
        // One movable contact indicates selection; alternatives are not wired
        // together. Stage 0 has no throw, unlike the three active selector positions.
        line(-40, 0, 20, -20),
        for (final p in symbolPins(s).skip(1)) ...[
          line(40, p['y'], 60, p['y']),
          circle(40, p['y'], 4),
        ],
        text(s.key == 'stage_switch_3pos' ? '0/1/2' : '1/2/3', -20, 40),
      ],
      'buzzer' => [
        ...stem,
        rect(-20, -20, 20, 20),
        line(20, -20, 40, -30),
        line(20, 20, 40, 30),
        text('~', -10, -10),
      ],
      'voltmeter' || 'ammeter' => [
        ...stem,
        circle(0, 0, 20),
        text(s.key == 'voltmeter' ? 'V' : 'A', -10, -10),
      ],
      'solar_cell' => [
        ...stem,
        circle(0, 0, 20),
        text('PV', -10, -10),
        line(-40, -30, -20, -10),
        line(-40, -10, -20, 10),
      ],
      _ => <Map<String, dynamic>>[],
    };
  }
  if (s.group == 'Automatisierung')
    return [
      rect(
        -60,
        -(s.ports.length ~/ 2 - 1) * 20 - 10,
        60,
        (s.ports.length ~/ 2 - 1) * 20 + 10,
      ),
      text(s.key.toUpperCase(), -20, -10),
      for (final p in symbolPins(s))
        line(p['x'], p['y'], (p['x'] as num) < 0 ? -60 : 60, p['y']),
    ];
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
    line(0, -40, 0, -20),
    line(0, 20, 0, 40),
    if (s.key == 'switch' || s.isContact) ...[
      line(0, 20, s.role == 'nc' ? 0 : 20, s.role == 'nc' ? -20 : -10),
      circle(0, -20, 4),
      circle(0, 20, 4),
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
              e.key:
                  e.key == 'radius' &&
                      s.group != 'Schutzgeräte' &&
                      snap(e.value) < 10
                  ? 10
                  : e.key == 'radius' && s.group == 'Schutzgeräte'
                  ? e.value
                  : e.value is num
                  ? snap(e.value)
                  : e.value,
          },
    ],
  };
}
