import 'dart:convert';
import 'dart:io';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';
import '../../ecad_core/bin/planning_sample.dart';
import 'package:company_users_service/src/workspace/pdf_output.dart';
import 'package:company_users_service/src/workspace/git_archive.dart';

void main() {
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
        expect(svg, contains('d="M$x 380 L${x + 10} 410"'), reason: key);
        expect(svg, contains('d="M${x + 10} 410 L$x 420"'), reason: key);
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
    );
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
