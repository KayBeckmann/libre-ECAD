import 'dart:convert';
import 'dart:math';

import 'package:company_users_service/src/workspace/pdf_output.dart';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'rotated symbol primitives follow each quarter-turn in SVG and PDF',
    () async {
      for (final angle in [0, 90, 180, 270]) {
        final d = emptyDrawing();
        final sheet = objects(d, 'sheets').first['id'] as String;
        final instance = addSymbol(d, 'breaker', sheet, 400, 400);
        instance['rotation'] = angle;
        final shape = symbolGeometry(symbolByKey('breaker')).firstWhere(
          (s) =>
              s['kind'] == 'line' && (s['x'] != s['x2'] || s['y'] != s['y2']),
        );
        Point<num> turn(num x, num y) => switch (angle) {
          90 => Point(400 - y, 400 + x),
          180 => Point(400 - x, 400 - y),
          270 => Point(400 + y, 400 - x),
          _ => Point(400 + x, 400 + y),
        };
        final a = turn(shape['x'], shape['y']);
        final b = turn(shape['x2'], shape['y2']);
        final svg = sheetSvg(d, sheet);
        expect(
          svg,
          contains('d="M${a.x} ${a.y} L${b.x} ${b.y}"'),
          reason: '$angle',
        );
        final pdf = await projectPdf(
          {'id': 'rotation', 'name': 'Rotation', 'version': 1, 'drawing': d},
          status: 'TEST',
          stamp: 'V1',
        );
        expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      }
    },
  );

  test(
    'moved wire waypoints keep endpoints fixed and segments orthogonal',
    () async {
      final d = emptyDrawing();
      final sheet = objects(d, 'sheets').first['id'] as String;
      final wire = <String, dynamic>{
        'id': 'wire',
        'sheetId': sheet,
        'from': {'kind': 'node', 'id': 'start'},
        'to': {'kind': 'node', 'id': 'end'},
        'waypoints': [
          {'x': 320, 'y': 280},
        ],
      };
      (d['nodes'] as List).addAll(<Json>[
        {'id': 'start', 'sheetId': sheet, 'x': 200, 'y': 200},
        {'id': 'end', 'sheetId': sheet, 'x': 500, 'y': 400},
      ]);
      (d['wires'] as List).add(wire);
      final points = routedWirePoints(d, wire);
      expect(points.first, const Point<double>(200, 200));
      expect(points.last, const Point<double>(500, 400));
      expect(points, contains(const Point<double>(320, 280)));
      final svg = sheetSvg(d, sheet);
      for (var j = 1; j < points.length; j++) {
        expect(
          points[j - 1].x == points[j].x || points[j - 1].y == points[j].y,
          isTrue,
        );
        expect(
          svg,
          contains(
            'd="M${points[j - 1].x} ${points[j - 1].y} L${points[j].x} ${points[j].y}"',
          ),
        );
      }
      final pdf = await projectPdf(
        {'id': 'waypoints', 'name': 'Waypoints', 'version': 1, 'drawing': d},
        status: 'TEST',
        stamp: 'V1',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    },
  );

  test(
    'automatic route skirts unrelated symbol body, including blocked endpoint column',
    () async {
      final d = emptyDrawing();
      final sheet = objects(d, 'sheets').first['id'] as String;
      final obstacle = addSymbol(d, 'breaker', sheet, 400, 300);
      final wire = <String, dynamic>{
        'id': 'wire',
        'sheetId': sheet,
        'from': {'kind': 'node', 'id': 'start'},
        'to': {'kind': 'node', 'id': 'end'},
      };
      (d['nodes'] as List).addAll(<Json>[
        {'id': 'start', 'sheetId': sheet, 'x': 400, 'y': 200},
        {'id': 'end', 'sheetId': sheet, 'x': 400, 'y': 400},
      ]);
      (d['wires'] as List).add(wire);
      final points = routedWirePoints(d, wire);
      expect(points.first, const Point<double>(400, 200));
      expect(points.last, const Point<double>(400, 400));
      expect(points.length, greaterThan(2));
      for (var j = 1; j < points.length; j++) {
        final a = points[j - 1], b = points[j];
        expect(a.x == b.x || a.y == b.y, isTrue);
        expect(
          !(a.x == b.x &&
                  a.x > 352 &&
                  a.x < 448 &&
                  max(a.y, b.y) > 276 &&
                  min(a.y, b.y) < 324) &&
              !(a.y == b.y &&
                  a.y > 276 &&
                  a.y < 324 &&
                  max(a.x, b.x) > 352 &&
                  min(a.x, b.x) < 448),
          isTrue,
        );
        expect(
          sheetSvg(d, sheet),
          contains('d="M${a.x} ${a.y} L${b.x} ${b.y}"'),
        );
      }
      expect(obstacle['sheetId'], sheet);
      final pdf = await projectPdf(
        {'id': 'obstacle', 'name': 'Obstacle', 'version': 1, 'drawing': d},
        status: 'TEST',
        stamp: 'V1',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    },
  );
}
