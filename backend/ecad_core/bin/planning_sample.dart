import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:image/image.dart' as image;

/// Synthetic acceptance fixture; no customer or manufacturer drawing data.
Json planningSample() {
  final d = emptyDrawing();
  final sid = objects(d, 'sheets').first['id'];
  objects(d, 'sheets').first['title'] = 'TEST Installation';
  final a = addSymbol(d, 'terminal', sid, 160, 200);
  final b = addSymbol(d, 'switch', sid, 560, 200);
  final plc = addSymbol(d, 'plc', sid, 800, 400);
  final background = image.Image(width: 800, height: 400);
  image.fill(background, color: image.ColorRgb8(243, 244, 240));
  image.drawRect(
    background,
    x1: 30,
    y1: 30,
    x2: 770,
    y2: 370,
    color: image.ColorRgb8(130, 140, 145),
    thickness: 4,
  );
  image.drawLine(
    background,
    x1: 400,
    y1: 30,
    x2: 400,
    y2: 260,
    color: image.ColorRgb8(130, 140, 145),
    thickness: 4,
  );
  d['plans'] = [
    {
      'id': sid,
      'kind': 'installation',
      'background': {
        'png': base64Encode(image.encodePng(background)),
        'origin': 'Synthetischer TEST-Grundriss',
        'revision': 'TEST-1',
        'locked': true,
        'x': 80,
        'y': 80,
        'width': 960,
        'height': 480,
      },
      'calibration': {
        'a': {'x': 160, 'y': 200},
        'b': {'x': 560, 'y': 200},
        'metres': 10,
        'source': 'TEST Referenz 10 m',
        'perspectiveConfirmed': true,
      },
      'circuits': [
        {
          'id': 'circuit-test',
          'name': 'Licht TEST',
          'distribution': 'UV-TEST',
          'deviceIds': [a['deviceId'], b['deviceId']],
        },
      ],
      'routes': [
        {
          'id': 'route-test',
          'name': 'TEST Leitung',
          'from': a['id'],
          'to': b['id'],
          'points': <Json>[],
          'circuitId': 'circuit-test',
          'allowanceM': 2,
        },
      ],
    },
  ];
  for (final dev in objects(d, 'devices')) {
    dev['article'] = articleSnapshot({
      'id': 'synthetic-${dev['type']}',
      'version': 1,
      'articleNumber': 'TEST-${dev['type']}',
      'name': 'TEST ${dev['type']}',
      'origin': 'Eigener synthetischer Test',
      'license': 'CC0-1.0',
      'layers': {
        'mechanical': {'widthMm': 80, 'heightMm': 120, 'depthMm': 60},
        'thermal': {'powerLossW': 4, 'conditions': 'Synthetische Volllast'},
      },
    });
  }
  objects(
    d,
    'devices',
  ).firstWhere((v) => v['id'] == plc['deviceId'])['channels'] = [
    {
      'id': 'I0',
      'module': plc['deviceId'],
      'port': 'I0',
      'signal': 'TEST Freigabe',
    },
  ];
  d['calculations'] = [
    {
      'id': 'voltage-test',
      'name': 'TEST Spannungsfall',
      'kind': 'voltage',
      'source': 'Synthetische Eingaben',
      'conditions': 'Symmetrische induktive Last TEST',
      'phase': 'balanced3',
      'routeId': 'route-test',
      'inputs': {
        'currentA': 10,
        'voltageV': 400,
        'lengthM': null,
        'areaMm2': 2.5,
        'resistanceOhmPerKm': 8,
        'reactanceOhmPerKm': 0.1,
        'cosPhi': 0.8,
        'limitPercent': 3,
        'ampacityA': 20,
        'breakerA': 16,
      },
    },
    {
      'id': 'thermal-test',
      'name': 'TEST Verlustleistung',
      'kind': 'thermal',
      'source': 'Synthetische Eingaben',
      'conditions': 'Stationaer TEST',
      'deviceIds': objects(d, 'devices').map((v) => v['id']).toList(),
      'inputs': {'ambientC': 25, 'insideC': 35, 'areaM2': 1, 'coefficient': 5},
    },
  ];
  return validateDrawing(d);
}

void main() {
  final project = <String, dynamic>{
    'id': 'test-m7',
    'name': 'TEST M7 Installation',
    'version': 1,
    'drawing': planningSample(),
  };
  print(
    jsonEncode({
      'project': project,
      'material': materialPacket(project, source: 'http://test.invalid'),
    }),
  );
}
