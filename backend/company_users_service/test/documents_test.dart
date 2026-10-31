import 'dart:convert';
import 'dart:io';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';
import '../../ecad_core/bin/planning_sample.dart';
import 'package:company_users_service/src/workspace/pdf_output.dart';
import 'package:company_users_service/src/workspace/git_archive.dart';

void main() {
  test('terminal strip identifier and short mark replace internal BMK in SVG', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first['id'] as String;
    final i = addSymbol(d, 'terminal', sheet, 400, 400);
    final device = objectById(d, 'devices', i['deviceId']);
    final internalBmk = device['bmk'] as String;
    final strip = createTerminalStrip(d, 'X100');
    assignTerminalToStrip(d, device['id'], strip['id'], 'PE');
    final svg = sheetSvg(d, sheet);
    expect(svg, contains('X100'));
    expect(svg, contains('PE'));
    expect(svg, isNot(contains(internalBmk)));
  });

  test('protective glyphs keep fine contacts in SVG and PDF export', () async {
    for (final key in [
      'mcb1',
      'mcb2',
      'mcb3',
      'rcd2',
      'rcd4',
      'rcbo2',
      'rcbo4',
    ]) {
      final d = emptyDrawing();
      final sid = objects(d, 'sheets').first['id'] as String;
      addSymbol(d, key, sid, 400, 400);
      final svg = sheetSvg(d, sid);
      final poles = symbolPins(symbolByKey(key)).length ~/ 2;
      expect(
        RegExp(r'<circle cx="\d+" cy="\d+" r="4"').allMatches(svg),
        hasLength(poles * 2),
        reason: key,
      );
      for (final p in symbolPins(symbolByKey(key)).take(poles)) {
        final x = 400 + (p['x'] as num);
        expect(svg, contains('d="M$x 420 L${x + 20} 390"'), reason: key);
        expect(svg, isNot(contains('d="M$x 380 L${x + 20} 390"')), reason: '$key must show an open gap');
      }
      final pdf = await projectPdf(
        {
          'id': 'protective-$key',
          'name': 'Schutzgeräte',
          'version': 1,
          'drawing': d,
        },
        status: 'TEST',
        stamp: 'V1',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF', reason: key);
    }
  });

  test('schematic keeps its original coordinates inside the page frame', () {
    final d = emptyDrawing();
    final sid = objects(d, 'sheets').first['id'] as String;
    addSymbol(d, 'breaker', sid, 400, 300);
    final svg = sheetSvg(d, sid);
    expect(svg, isNot(contains('<g transform=')));
    expect(svg, contains('x="12" y="20" width="1176" height="760"'));
    expect(svg, contains('x="40" y="60" width="1120" height="640"'));
  });

  test(
    'PDF sheet uses only the framed title block, not extra page furniture',
    () async {
      final d = emptyDrawing();
      final sid = objects(d, 'sheets').first['id'] as String;
      addSymbol(d, 'breaker', sid, 400, 300);
      final pdf = await projectPdf(
        {'id': 'sheet-fit', 'name': 'Rahmenbreite', 'version': 1, 'drawing': d},
        status: 'NICHT FREIGEGEBEN',
        stamp: 'V1',
      );
      final dir = await Directory.systemTemp.createTemp('libre-sheet-fit-');
      try {
        final file = File('${dir.path}/sheet.pdf');
        await file.writeAsBytes(pdf);
        final result = await Process.run('pdftotext', [
          '-f',
          '3',
          '-l',
          '3',
          '-layout',
          file.path,
          '-',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final text = result.stdout as String;
        expect(text, contains('Stromlaufplan'));
        expect(text, isNot(contains('Blatt 1 - Stromlaufplan')));
        expect(
          RegExp('Symbolherkunft siehe Projektstand').allMatches(text),
          hasLength(1),
        );
        expect(text, contains('Keine Normprüfung oder Konformitätsaussage.'));
        expect(text, isNot(contains('V1 | NICHT FREIGEGEBEN | V1')));
        final raster = await Process.run('pdftoppm', [
          '-f',
          '3',
          '-l',
          '3',
          '-r',
          '72',
          '-gray',
          '-singlefile',
          file.path,
          '${dir.path}/page',
        ]);
        expect(raster.exitCode, 0, reason: '${raster.stderr}');
        final pixels = await File('${dir.path}/page.pgm').readAsBytes();
        final header = RegExp(
          r'^P5\s+(\d+)\s+(\d+)\s+255\s',
        ).firstMatch(latin1.decode(pixels.take(40).toList()));
        expect(header, isNotNull);
        final width = int.parse(header![1]!);
        final height = int.parse(header[2]!);
        final row = height ~/ 2;
        final dark = [
          for (var x = 0; x < width; x++)
            if (pixels[header.end + row * width + x] < 128) x,
        ];
        expect(dark, isNotEmpty);
        expect(dark.first, lessThan(40), reason: 'left frame edge');
        expect(width - dark.last, lessThan(40), reason: 'right frame edge');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('exported SVG has the same framed title and persisted revisions', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first;
    sheet['title'] = 'Verteiler <West>';
    sheet['revisions'] = [
      {'revision': 'A', 'date': '2025-03-17', 'note': 'Prüfung & Korrektur'},
    ];
    final svg = sheetSvg(
      d,
      sheet['id'],
      projectName: 'Projekt <Nord>',
      version: 7,
      stamp: 'T-MpinL5',
    );
    expect(svg, contains('T-MpinL5'));
    expect(svg, contains('Keine Normprüfung oder Konformitätsaussage.'));
    expect(svg, contains('REVISION &#47; DATUM &#47; NOTIZ'));
    expect(svg, contains('A  2025-03-17  Prüfung &amp; Korrektur'));
    expect(svg, contains('Verteiler &lt;West&gt;'));
    expect(svg, contains('Projekt &lt;Nord&gt;'));
    expect(svg, contains('BLATT 1 &#47; 1'));
    expect(svg, contains('Arbeitsstand 7'));
    expect(svg, contains('Nicht fachlich freigegeben'));
    expect(svg, contains('x="12" y="20" width="1176" height="760"'));
    final approved = sheetSvg(
      d,
      sheet['id'],
      reviewStatus: 'FACHLICH FESTGESCHRIEBEN',
    );
    expect(approved, contains('FACHLICH FESTGESCHRIEBEN'));
    expect(approved, isNot(contains('Nicht fachlich freigegeben')));
  });
  test(
    'SVG puts contact comb below coil and contacts reference only the coil',
    () {
      final d = sampleDrawing('three-phase');
      final coil = objects(
        d,
        'instances',
      ).firstWhere((i) => symbolByKey(i['symbol'], d).role == 'coil');
      final reference = positionReference(d, coil);
      final sheets = objects(d, 'sheets');
      final all = sheets.map((s) => sheetSvg(d, s['id'])).join();
      expect(all, contains('Kontaktkamm'));
      expect(all, contains('Öffner'));
      expect(all, contains('Schließer'));
      final labels = RegExp(
        r'>Ref\. ([^<]+)</text>',
      ).allMatches(all).map((m) => m[1]).toList();
      expect(labels, hasLength(3));
      expect(labels.toSet(), {const HtmlEscape().convert(reference)});
      expect(sheetSvg(d, coil['sheetId']), contains('y="${coil['y'] + 52}"'));
    },
  );

  test(
    'linked NO has a gap and NC closes against its upper contact in SVG/PDF',
    () async {
      final d = sampleDrawing('three-phase');
      final coil = objects(
        d,
        'instances',
      ).firstWhere((i) => symbolByKey(i['symbol'], d).role == 'coil');
      final comb = relayContactComb(d, coil);
      final svg = sheetSvg(d, coil['sheetId']);
      final no = comb.firstWhere((c) => c['role'] != 'nc');
      final nc = comb.firstWhere((c) => c['role'] == 'nc');
      final num nx = no['x'], ny = no['y'], cx = nc['x'], cy = nc['y'];
      expect(svg, contains('d="M$nx ${ny + 8} L${nx + 8} ${ny - 3}"'));
      expect(svg, contains('d="M$nx ${ny - 15} L$nx ${ny - 8}"'));
      expect(svg, contains('d="M$cx ${cy + 8} L${cx + 8} ${cy - 8}"'));
      expect(svg, contains('d="M${cx + 8} ${cy - 15} L${cx + 8} ${cy - 8}"'));
      for (final contact in [no, nc]) {
        expect(
          svg,
          contains(
            '>${const HtmlEscape().convert(contact['terminals'].join('/'))}</text>',
          ),
        );
        expect(
          svg,
          contains(
            '>${const HtmlEscape().convert(contact['position'].toString())}</text>',
          ),
        );
      }
      final pdf = await projectPdf(
        {'id': 'comb', 'name': 'Kontaktkamm', 'version': 1, 'drawing': d},
        status: 'TEST',
        stamp: 'V1',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      final dir = await Directory.systemTemp.createTemp('libre-contact-comb-');
      try {
        final file = File('${dir.path}/comb.pdf');
        await file.writeAsBytes(pdf);
        final result = await Process.run('pdftotext', [
          '-layout',
          file.path,
          '-',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final text = result.stdout as String;
        for (final contact in [no, nc]) {
          expect(text, contains(contact['terminals'].join('/')));
          expect(text, contains(contact['position']));
        }
        expect(text, contains('Ref. ${positionReference(d, coil)}'));
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'installation PNG, scale, circuits and calculation evidence render in PDF',
    () async {
      final d = planningSample();
      final svg = sheetSvg(d, objects(d, 'sheets').first['id']);
      expect(svg, contains('data:image/png;base64,'));
      expect(svg, contains('12.00 m'));
      final pdf = await projectPdf(
        {'id': 'm7', 'name': 'TEST M7', 'version': 1, 'drawing': d},
        status: 'TEST NICHT FREIGEGEBEN',
        stamp: 'V1',
      );
      expect(pdf.length, greaterThan(10000));
      await File('/tmp/libre-m7-render.pdf').writeAsBytes(pdf);
    },
  );
  test(
    'three-phase and custom symbols render into SVG and PDF with provenance',
    () async {
      final d = threePhaseDrawing();
      final symbol = symbolTemplate('contact_nc', 'custom-test');
      symbol['primitives'].add({
        'kind': 'text',
        'x': 40,
        'y': 40,
        'text': 'CUSTOM<&>',
      });
      final key = pinArticleSymbol(d, {
        'id': 'article-test',
        'version': 2,
        'origin': 'Eigener Test',
        'layers': {
          'symbol': {'definition': symbol, 'license': 'CC0'},
        },
      });
      final sid = objects(d, 'sheets').first['id'];
      addSymbol(d, key, sid, 900, 500);
      final svg = sheetSvg(d, sid);
      expect(svg, contains('CUSTOM&lt;&amp;&gt;'));
      expect(svg, contains('L1'));
      expect(svg, contains('PE'));
      final pdf = await projectPdf(
        {'id': 'symbols', 'name': 'Symbole', 'version': 2, 'drawing': d},
        status: 'TEST',
        stamp: 'V2',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      await File('/tmp/libre-symbols-test.pdf').writeAsBytes(pdf);
    },
  );
  test(
    'PDF sheets and derived lists; archive reconstructs exact commit',
    () async {
      final project = <String, dynamic>{
        'id': 'test',
        'version': 4,
        'name': 'Prüfprojekt ÄÖÜ',
        'description': 'Synthetischer Motorabgang',
        'metadata': {'Kunde': 'Testfirma'},
        'drawing': sampleDrawing('motor'),
      };
      final data = documentData(project);
      expect(
        (data['material'] as List).length,
        objects(project['drawing'], 'devices').length,
      );
      final pdf = await projectPdf(
        project,
        status: 'ARBEITSSTAND - NICHT FREIGEGEBEN',
        stamp: 'V4',
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      await File('/tmp/libre-m5-test.pdf').writeAsBytes(pdf);
      final root = await Directory.systemTemp.createTemp('ecad-archive-test-');
      try {
        final packet = <String, dynamic>{
          'id': 'test',
          'at': '2026-10-24T12:00:00Z',
          'files': {
            'project.json': base64Encode(utf8.encode(canonicalJson(project))),
            'output.pdf': base64Encode(pdf),
          },
        };
        final archive = GitArchive(root.path);
        final commit = await archive.write('company', 'test', packet);
        packet['commit'] = commit;
        await root.delete(recursive: true);
        expect(await archive.write('company', 'test', packet), commit);
        final second = <String, dynamic>{
          ...packet,
          'id': 'second',
          'parent': commit,
        }..remove('commit');
        expect(await archive.write('company', 'test', second), isNot(commit));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'maximum sheet count and multiline text paginate without omission',
    () async {
      final d = emptyDrawing();
      d['sheets'] = <Json>[
        for (var i = 1; i <= 50; i++)
          {'id': 'sheet-$i', 'number': i, 'title': 'Blatt $i'},
      ];
      final project = <String, dynamic>{
        'id': 'large',
        'name': 'Paginierung',
        'version': 9,
        'description':
            '${List.filled(100, 'Zeile mit langem Inhalt und Umlauten ÄÖÜ.').join('\n')} ENDMARKER',
        'metadata': {},
        'drawing': d,
      };
      final pdf = await projectPdf(
        project,
        status: 'ARBEITSSTAND',
        stamp: 'V9',
      );
      expect(pdf.length, greaterThan(10000));
      await File('/tmp/libre-m5-long.pdf').writeAsBytes(pdf);
    },
  );
}
