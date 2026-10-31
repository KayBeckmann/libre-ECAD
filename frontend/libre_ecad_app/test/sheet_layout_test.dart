import 'dart:ui' as ui;

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/drawing/drawing_canvas.dart';

void main() {
  test(
    'canvas linked NO gap and NC joined blade preserve the comb labels',
    () async {
      final drawing = sampleDrawing('three-phase');
      final coil = objects(
        drawing,
        'instances',
      ).firstWhere((i) => symbolByKey(i['symbol'], drawing).role == 'coil');
      final comb = relayContactComb(drawing, coil);
      final no = comb.firstWhere((c) => c['role'] != 'nc');
      final nc = comb.firstWhere((c) => c['role'] == 'nc');
      expect(no['terminals'], isNotEmpty);
      expect(nc['terminals'], isNotEmpty);
      expect(no['position'], isNotEmpty);
      expect(nc['position'], isNotEmpty);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      SheetPainter(
        drawing,
        coil['sheetId'],
        'P',
        1,
        null,
      ).paint(canvas, const Size(1200, 800));
      final image = await recorder.endRecording().toImage(1200, 800);
      addTearDown(image.dispose);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int redAt(int x, int y) => pixels.getUint8((y * 1200 + x) * 4);
      final nx = (no['x'] as num).toInt(), ny = (no['y'] as num).toInt();
      final cx = (nc['x'] as num).toInt(), cy = (nc['y'] as num).toInt();
      expect(redAt(nx, ny - 4), 255, reason: 'NO visible air gap');
      expect(redAt(nx + 4, ny + 2), lessThan(200), reason: 'NO moving blade');
      expect(
        redAt(cx + 8, cy - 11),
        lessThan(200),
        reason: 'NC upper terminal',
      );
      expect(redAt(cx + 4, cy), lessThan(200), reason: 'NC closed blade');
    },
  );

  test('background stays visible only inside the drawing field', () async {
    final drawing = emptyDrawing();
    final sheetId = objects(drawing, 'sheets').first['id'] as String;
    drawing['plans'] = [
      {
        'id': sheetId,
        'kind': 'layout',
        'mmPerUnit': 1,
        'routes': [],
        'background': {'png': '', 'x': 0, 'y': 0, 'width': 1200, 'height': 800},
      },
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.red, BlendMode.src);
    SheetPainter(
      drawing,
      sheetId,
      'P',
      1,
      null,
    ).paint(canvas, const Size(1200, 800));
    final image = await recorder.endRecording().toImage(1200, 800);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    addTearDown(image.dispose);
    Color pixel(int x, int y) {
      final offset = (y * 1200 + x) * 4;
      return Color.fromARGB(
        255,
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    }

    expect(pixel(401, 301).toARGB32(), Colors.red.toARGB32());
    expect(pixel(2, 301), Colors.white);
    expect(pixel(2, 750), Colors.white);
  });

  test(
    'footer shows only the four latest persisted revisions or an empty label',
    () {
      final drawing = emptyDrawing();
      final sheet = objects(drawing, 'sheets').first;
      final sheetId = sheet['id'] as String;
      expect(
        SheetTitleBlockData.fromDrawing(drawing, sheetId, 'P', 1).revisionRows,
        ['Keine Revisionen erfasst'],
      );
      sheet['revisions'] = List.generate(
        6,
        (i) => {
          'revision': 'R$i',
          'date': '2025-01-0${i + 1}',
          if (i == 5) 'note': 'Abnahmevorbereitung',
        },
      );
      expect(
        SheetTitleBlockData.fromDrawing(drawing, sheetId, 'P', 1).revisionRows,
        [
          'R5  2025-01-06  Abnahmevorbereitung',
          'R4  2025-01-05',
          'R3  2025-01-04',
          'R2  2025-01-03',
        ],
      );
    },
  );

  test('title block derives actual sheet and project metadata only', () {
    final drawing = emptyDrawing();
    final sheet = objects(drawing, 'sheets').first;
    sheet['number'] = 3;
    sheet['title'] = 'Verteilung West';
    objects(
      drawing,
      'sheets',
    ).add({'id': 'second', 'number': 4, 'title': 'Anhang'});

    final block = SheetTitleBlockData.fromDrawing(
      drawing,
      sheet['id'] as String,
      'Projekt Nord',
      7,
    );
    expect(block.title, 'Verteilung West');
    expect(block.project, 'Projekt Nord');
    expect(block.sheet, '3 / 2');
    expect(block.status, 'Arbeitsstand 7');
    expect(block.warning, 'Nicht fachlich freigegeben');
    expect(block.toString(), isNot(contains('Bearbeiter')));
    expect(block.toString(), isNot(contains('Datum')));
  });

  test(
    'closed frame and boxed zones render outside untouched drawing field',
    () async {
      final drawing = emptyDrawing();
      final sheetId = objects(drawing, 'sheets').first['id'] as String;
      final recorder = ui.PictureRecorder();
      SheetPainter(
        drawing,
        sheetId,
        'Projekt',
        1,
        null,
      ).paint(Canvas(recorder), const Size(1200, 800));
      final image = await recorder.endRecording().toImage(1200, 800);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      addTearDown(image.dispose);
      Color pixel(int x, int y) {
        final offset = (y * 1200 + x) * 4;
        return Color.fromARGB(
          255,
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      // Outer perimeter; top column separator; left row separator; title-block partitions.
      for (final point in [
        const Offset(12, 400),
        const Offset(600, 20),
        const Offset(152, 40),
        const Offset(26, 160),
        const Offset(440, 730),
        const Offset(850, 730),
      ]) {
        final sampled = pixel(point.dx.toInt(), point.dy.toInt());
        expect((sampled.r * 255).round(), lessThan(180), reason: '$point');
      }
      // White, unoccluded drawing surface between grid points.
      expect(pixel(401, 301), Colors.white);
      expect(pixel(600, 690), Colors.white);
    },
  );
}
