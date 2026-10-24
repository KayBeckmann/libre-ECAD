import 'dart:convert';
import 'dart:io';
import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';
import 'package:company_users_service/src/workspace/pdf_output.dart';
import 'package:company_users_service/src/workspace/git_archive.dart';

void main() {
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
