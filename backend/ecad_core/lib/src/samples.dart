import 'drawing.dart';

/// Synthetic working examples, not installation plans.
Json sampleDrawing(String kind) {
  if (kind == 'three-phase') return threePhaseDrawing();
  if (kind != 'distribution' && kind != 'motor')
    throw FormatException('Unbekannte Arbeitsprobe.');
  final d = emptyDrawing();
  final first = objects(d, 'sheets').first;
  first['title'] = kind == 'distribution'
      ? 'TEST · Verteilerabgang'
      : 'TEST · Motorabgang';
  final second = {
    'id': newId(),
    'number': 2,
    'title': 'TEST · Steuerung / Fortsetzung',
  };
  (d['sheets'] as List).add(second);
  final a = first['id'] as String, b = second['id'] as String;
  void wire(String sheet, Json from, Json to, {String? cable, String? core}) {
    (d['wires'] as List).add({
      'id': newId(),
      'sheetId': sheet,
      'from': from,
      'to': to,
      if (cable != null) 'cableId': cable,
      if (core != null) 'coreId': core,
    });
  }

  final supply = addSymbol(d, 'supply', a, 200, 160);
  final breaker = addSymbol(d, 'breaker', a, 200, 320);
  final terminal = addSymbol(d, 'terminal', a, 200, 480);
  final relay = addSymbol(d, 'coil', b, 600, 320);
  final contact = addSymbol(
    d,
    'contact',
    a,
    600,
    320,
    deviceId: relay['deviceId'],
  );
  wire(a, portRef(supply['id'], 'N'), portRef(breaker['id'], '1'));
  final cable = {
    'id': newId(),
    'bmk': 'W1',
    'cores': [
      {'id': '1', 'label': '1', 'color': 'nicht festgelegt'},
    ],
  };
  (d['cables'] as List).add(cable);
  wire(
    a,
    portRef(breaker['id'], '2'),
    portRef(terminal['id'], '1'),
    cable: cable['id'] as String,
    core: '1',
  );
  final link = newId();
  final ca = {
    'id': newId(),
    'sheetId': a,
    'x': 600,
    'y': 520,
    'linkId': link,
    'label': 'TEST-Signal',
  };
  final cb = {
    'id': newId(),
    'sheetId': b,
    'x': 600,
    'y': 160,
    'linkId': link,
    'label': 'TEST-Signal',
  };
  (d['continuations'] as List).addAll(<Json>[ca, cb]);
  wire(
    a,
    portRef(contact['id'], '14'),
    pointRef('continuation', ca['id'] as String),
  );
  wire(
    b,
    pointRef('continuation', cb['id'] as String),
    portRef(relay['id'], 'A1'),
  );
  if (kind == 'motor') {
    final motor = addSymbol(d, 'motor', a, 900, 520);
    wire(a, portRef(contact['id'], '13'), portRef(motor['id'], 'U'));
    final button = addSymbol(d, 'switch', b, 300, 320);
    wire(b, portRef(button['id'], '2'), portRef(relay['id'], 'A2'));
  } else {
    final branch = {'id': newId(), 'sheetId': a, 'x': 400, 'y': 480};
    (d['nodes'] as List).add(branch);
    wire(
      a,
      portRef(terminal['id'], '1'),
      pointRef('node', branch['id'] as String),
    );
    wire(
      a,
      pointRef('node', branch['id'] as String),
      portRef(contact['id'], '13'),
    );
    final output = addSymbol(d, 'terminal', a, 400, 600);
    wire(
      a,
      pointRef('node', branch['id'] as String),
      portRef(output['id'], '1'),
    );
  }
  return validateDrawing(d);
}

Json threePhaseDrawing() {
  final d = emptyDrawing(), sheet = objects(emptyDrawing(), 'sheets').first;
  sheet['title'] = 'TEST · Dreiphasiger Motorabgang';
  d['sheets'] = [sheet];
  final control = {
    'id': newId(),
    'number': 2,
    'title': 'TEST · Spule und zugeordnete Kontakte',
  };
  (d['sheets'] as List).add(control);
  final a = sheet['id'] as String, b = control['id'] as String;
  final supply = addSymbol(d, 'supply3', a, 300, 180),
      breaker = addSymbol(d, 'breaker3', a, 300, 360),
      motor = addSymbol(d, 'motor', a, 300, 580);
  void wire(Json from, String f, Json to, String t, String conductor) =>
      (d['wires'] as List).add({
        'id': newId(),
        'sheetId': a,
        'from': portRef(from['id'], f),
        'to': portRef(to['id'], t),
        'conductor': conductor,
      });
  for (var n = 0; n < 3; n++) {
    wire(supply, 'L${n + 1}', breaker, '${n * 2 + 1}', 'L${n + 1}');
    wire(breaker, '${n * 2 + 2}', motor, ['U', 'V', 'W'][n], 'L${n + 1}');
  }
  wire(supply, 'PE', motor, 'PE', 'PE');
  final coil = addSymbol(d, 'coil', b, 200, 300);
  addSymbol(d, 'contact', b, 460, 300, deviceId: coil['deviceId']);
  addSymbol(d, 'contact_nc', b, 720, 300, deviceId: coil['deviceId']);
  addSymbol(d, 'contact', a, 760, 380, deviceId: coil['deviceId']);
  return validateDrawing(d);
}
