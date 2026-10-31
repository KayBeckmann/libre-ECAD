import 'package:ecad_core/ecad_core.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/api/workspace_api.dart';
import 'package:libre_ecad_app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/screens/drawing_screen.dart';
import 'package:libre_ecad_app/src/screens/documents_screen.dart';

void main() {
  testWidgets(
    'inspector assigns and renumbers separate terminals on one strip',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final drawing = emptyDrawing();
      final sheet = objects(drawing, 'sheets').first['id'] as String;
      addSymbol(drawing, 'terminal', sheet, 200, 200);
      addSymbol(drawing, 'terminal', sheet, 360, 200);
      final devices = objects(drawing, 'devices');
      final session = Session(
        token: 'test',
        username: 'test',
        role: UserRole.zeichner,
        companyName: 'TEST',
        backendUrl: Uri.parse('http://localhost'),
      );
      Json? saved;
      final api = WorkspaceApi(
        session,
        client: MockClient((request) async {
          if (request.method == 'PUT') {
            saved = (jsonDecode(request.body) as Json)['drawing'];
          }
          return http.Response(
            jsonEncode({
              'projectName': 'Klemmen',
              'version': saved == null ? 1 : 2,
              'drawing': saved ?? drawing,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(session: session, projectId: 'p', api: api),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> selectAndAssign(int index, {String? mark}) async {
        final symbol = find.bySemanticsLabel('Symbol ${devices[index]['bmk']}');
        await tester.tapAt(tester.getCenter(symbol) + const Offset(35, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Klemmenleiste / Markierung'));
        await tester.pumpAndSettle();
        if (mark != null) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Markierung (max. 3 Zeichen)'),
            mark,
          );
        }
        await tester.tap(find.text('Übernehmen'));
        await tester.pumpAndSettle();
      }

      await selectAndAssign(0);
      await selectAndAssign(1);
      expect(find.text('X1:2'), findsOneWidget);
      await selectAndAssign(1, mark: 'PE');
      expect(find.text('X1:PE'), findsOneWidget);
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(objects(saved!, 'devices').map((d) => d['terminals'][0]['id']), [
        '1',
        '1',
      ]);
      expect(
        objects(saved!, 'devices').map((d) => d['terminals'][0]['label']),
        ['1', 'PE'],
      );
      expect(
        objects(saved!, 'devices').map((d) => d['id']).toSet(),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  test(
    'palette groups and symbols are ordered without changing symbol keys',
    () {
      final groups = orderedPaletteGroups(emptyDrawing());
      expect(groups.first, 'Verteilerabgang');
      expect(
        groups.indexOf('Steuer- / Motorabgang'),
        lessThan(groups.indexOf('Drehstrom')),
      );
      expect(
        groups.indexOf('Elektronik'),
        lessThan(groups.indexOf('Anschlussklemmen')),
      );
      final symbols = orderedPaletteSymbols(
        emptyDrawing(),
        'Verteilerabgang',
        '',
      );
      expect(
        symbols.map((s) => s.name).toList(),
        orderedEquals(
          symbols.map((s) => s.name).toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        ),
      );
      expect(symbols.any((s) => s.key == 'terminal'), isTrue);
    },
  );

  test('strip assignment preserves independent device and port identities', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first['id'] as String;
    final a = addSymbol(d, 'terminal', sheet, 200, 200);
    final b = addSymbol(d, 'terminal', sheet, 320, 200);
    final devices = objects(d, 'devices');
    final before = devices
        .map((v) => [v['id'], v['bmk'], v['terminals'][0]['id']])
        .toList();
    assignTerminalStrip(d, devices.first, 'X1', '1');
    assignTerminalStrip(d, devices.last, 'X1', 'N');
    expect(objects(d, 'terminalStrips').single['bmk'], 'X1');
    expect(devices.map((v) => v['terminalStripId']).toSet().length, 1);
    expect(devices.map((v) => v['terminals'][0]['label']), ['1', 'N']);
    expect(
      devices.map((v) => [v['id'], v['bmk'], v['terminals'][0]['id']]).toList(),
      before,
    );
    expect(a['deviceId'], isNot(b['deviceId']));
    expect(
      () => assignTerminalStrip(d, devices.last, 'X1', '1'),
      throwsFormatException,
    );
    expect(
      () => assignTerminalStrip(d, devices.last, 'X1', 'LONG'),
      throwsFormatException,
    );
    expect(
      () => assignTerminalStrip(d, devices.last, 'X1', 'PE'),
      returnsNormally,
    );
    expect(nextTerminalMark(d, objects(d, 'terminalStrips').single['id']), '2');
  });

  test('terminal strip identifiers are freely chosen and case-insensitive', () {
    final d = emptyDrawing();
    final sheet = objects(d, 'sheets').first['id'] as String;
    addSymbol(d, 'terminal', sheet, 200, 200);
    addSymbol(d, 'terminal', sheet, 400, 200);
    final devices = objects(d, 'devices');
    assignTerminalStrip(d, devices.first, 'KLEM-24', '1');
    assignTerminalStrip(d, devices.last, 'klem-24', 'PE');
    expect(objects(d, 'terminalStrips'), hasLength(1));
    expect(devices.first['terminalStripId'], devices.last['terminalStripId']);
    expect(validateDrawing(d), d);
  });

  test('terminal overview groups strip members and keeps legacy rows', () {
    final groups = groupedTerminalRows([
      {'bmk': 'old', 'terminal': '1', 'connections': 1},
      {
        'bmk': 'X1',
        'terminalStripId': 'strip-one',
        'terminal': 'N',
        'connections': 0,
      },
      {
        'bmk': 'X1',
        'terminalStripId': 'strip-one',
        'terminal': '1',
        'connections': 2,
      },
      {
        'bmk': 'X2',
        'terminalStripId': 'strip-two',
        'terminal': 'PE',
        'connections': 0,
      },
    ]);
    expect(groups.keys.toList(), ['X1', 'X2', 'Ohne Klemmenleiste']);
    expect(groups['X1']!.map((r) => r['terminal']), ['1', 'N']);
    expect(groups['Ohne Klemmenleiste']!.single['bmk'], 'old');
  });

  test(
    'terminal overview orders numeric strip and terminal labels naturally',
    () {
      final groups = groupedTerminalRows([
        for (final strip in ['X100', 'X24', 'X2', 'X1'])
          for (final mark in ['10', '2', '1'])
            {'bmk': strip, 'terminalStripId': strip, 'terminal': mark},
      ]);
      expect(groups.keys.toList(), ['X1', 'X2', 'X24', 'X100']);
      expect(groups['X24']!.map((row) => row['terminal']), ['1', '2', '10']);
    },
  );
}
