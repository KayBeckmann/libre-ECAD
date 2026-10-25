import 'dart:convert';
import 'dart:typed_data';

import 'package:ecad_core/ecad_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String sheetSvg(Json d, String sheetId) {
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800"><rect width="1200" height="800" fill="white"/>',
  );
  String esc(Object? s) => const HtmlEscape().convert('$s');
  void line(num x, num y, num x2, num y2) => out.write(
    '<path d="M$x $y L$x2 $y2" fill="none" stroke="#203d4c" stroke-width="1.5"/>',
  );
  void label(Object? s, num x, num y, {int size = 12}) => out.write(
    '<text x="$x" y="$y" font-size="$size" fill="#203d4c">${esc(s)}</text>',
  );
  void rect(num x, num y, num w, num h) => out.write(
    '<rect x="$x" y="$y" width="$w" height="$h" fill="none" stroke="#203d4c"/>',
  );
  void circle(num x, num y, num radius, {bool fill = false}) => out.write(
    '<circle cx="$x" cy="$y" r="$radius" stroke="#203d4c" fill="${fill ? '#203d4c' : 'none'}"/>',
  );
  rect(40, 60, 1120, 640);
  for (var c = 0; c < 10; c++) {
    label(c + 1, 88 + c * 112, 45);
  }
  for (var r = 0; r < 6; r++) {
    label(String.fromCharCode(65 + r), 18, 110 + r * 100);
  }
  for (final w in objects(d, 'wires').where((w) => w['sheetId'] == sheetId)) {
    final a = endpointPosition(d, w['from']), b = endpointPosition(d, w['to']);
    final mid = ((a.y + b.y) / 40).round() * 20;
    line(a.x, a.y, a.x, mid);
    line(a.x, mid, b.x, mid);
    line(b.x, mid, b.x, b.y);
    if (w['cableId'] != null) {
      final c = objectById(d, 'cables', w['cableId']);
      final core = (c['cores'] as List).firstWhere(
        (v) => v['id'] == w['coreId'],
      );
      label('${c['bmk']}:${core['label']}', a.x + 6, mid - 5, size: 10);
    }
  }
  for (final i in objects(
    d,
    'instances',
  ).where((i) => i['sheetId'] == sheetId)) {
    final num x = i['x'], y = i['y'];
    final s = symbolByKey(i['symbol']);
    final dev = objectById(d, 'devices', i['deviceId']);
    if (s.key == 'terminal') {
      circle(x, y, 8);
      line(x - 5, y, x + 5, y);
    } else if (s.key == 'motor') {
      circle(x, y, 24);
      label('M', x - 8, y + 6, size: 20);
      for (final p in s.ports) {
        final pos = endpointPosition(d, portRef(i['id'], p));
        line(pos.x, pos.y, pos.x, y - 24);
      }
    } else {
      line(x, y - 40, x, y - 18);
      line(x, y + 18, x, y + 40);
      if (s.key == 'switch' || s.key == 'contact') {
        line(x, y + 18, x + 20, y - 18);
        circle(x, y - 18, 2);
        circle(x, y + 18, 2);
      } else {
        rect(x - 22, y - 18, 44, 36);
        label(s.code, x - 7, y + 5, size: 14);
      }
    }
    label(dev['bmk'], x + 32, y - 8, size: 14);
    label(dev['label'], x + 32, y + 10, size: 10);
    final refs = crossReferences(d, dev['id'])
        .where((v) => v['instanceId'] != i['id'])
        .map((v) => v['position'])
        .join(', ');
    if (refs.isNotEmpty) label('Ref. $refs', x + 32, y + 27, size: 10);
    for (final p in s.ports) {
      final pos = endpointPosition(d, portRef(i['id'], p));
      final t = (dev['terminals'] as List).firstWhere((t) => t['id'] == p);
      label(t['label'], pos.x - 26, pos.y - 2, size: 10);
    }
  }
  for (final n in objects(d, 'nodes').where((n) => n['sheetId'] == sheetId)) {
    circle(n['x'], n['y'], 5, fill: true);
  }
  for (final o in objects(
    d,
    'continuations',
  ).where((o) => o['sheetId'] == sheetId)) {
    final num x = o['x'], y = o['y'];
    line(x - 10, y - 9, x + 10, y);
    line(x + 10, y, x - 10, y + 9);
    final other = objects(
      d,
      'continuations',
    ).firstWhere((v) => v['linkId'] == o['linkId'] && v['id'] != o['id']);
    label(
      '${o['label']} -> ${positionReference(d, other)}',
      x + 16,
      y + 4,
      size: 11,
    );
  }
  out.write('</svg>');
  return out.toString();
}

Future<Uint8List> projectPdf(
  Json project, {
  required String status,
  required String stamp,
  Json? approval,
  required Uint8List regularFont,
  required Uint8List boldFont,
}) async {
  final data = documentData(project), d = project['drawing'] as Json;
  final regular = pw.Font.ttf(ByteData.sublistView(regularFont));
  final bold = pw.Font.ttf(ByteData.sublistView(boldFont));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: '${project['name']} - V${project['version']}',
    author: 'LibreECAD',
    creator: 'LibreECAD M5',
  );
  final sheets = (data['sheets'] as List).cast<Json>();
  final sections = <String, List<List<String>>>{
    'Projektbeschreibung': [
      ['Feld', 'Inhalt'],
      ['Beschreibung', '${project['description'] ?? ''}'],
      for (final e in (data['metadata'] as Map).entries)
        ['${e.key}', '${e.value}'],
    ],
    if (approval != null)
      'Prüfprotokoll': [
        ['Hinweis', 'Begründung'],
        ['Freigabe', '${approval['reason']}'],
        for (final e in (approval['exceptions'] as Map).entries)
          ['${e.key}', '${e.value}'],
      ],
    'Plausibilitätsprüfung': [
      ['Schweregrad', 'Objekt und Hinweis', 'Begründete Ausnahme'],
      for (final f in drawingFindings(d))
        [
          '${f['severity']}',
          '${f['id']}\n${f['message']}',
          '${approval?['exceptions']?[f['id']] ?? 'Nicht freigegeben / offen'}',
        ],
    ],
    'Klemmenliste': [
      ['BMK', 'Anschluss', 'Verbindungen'],
      for (final t in data['terminals'])
        ['${t['bmk']}', '${t['terminal']}', '${t['connections']}'],
    ],
    'Verbindungsliste': [
      ['Blatt', 'Von', 'Nach', 'Kabel / Ader'],
      for (final w in data['connections'])
        [
          '${w['sheet']}',
          '${w['from']}',
          '${w['to']}',
          '${w['cable']} / ${w['core']}',
        ],
    ],
    'Kabel- und Aderliste': [
      ['Kabel', 'Ader', 'Farbe', 'Verbindungen'],
      for (final c in data['cables'])
        ['${c['bmk']}', '${c['core']}', '${c['color']}', '${c['connections']}'],
    ],
    'Materialliste': [
      ['BMK', 'Bezeichnung', 'Typ', 'Anzahl', 'Positionen'],
      for (final m in data['material'])
        [
          '${m['bmk']}',
          '${m['label']}',
          '${m['type']}',
          '${m['quantity']}',
          '${m['positions']}',
        ],
    ],
  };
  // Bound individual rows so they can split across pages without losing long text.
  List<String> textParts(String text) {
    final parts = <String>[];
    var current = StringBuffer(), count = 0, lines = 0;
    for (final rune in text.runes) {
      current.writeCharCode(rune);
      count++;
      if (rune == 10) lines++;
      if (count >= 180 || lines >= 4) {
        parts.add(current.toString());
        current = StringBuffer();
        count = 0;
        lines = 0;
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }

  final tables = <String, List<List<String>>>{};
  for (final entry in sections.entries) {
    final rows = <List<String>>[entry.value.first];
    for (final original in entry.value.skip(1)) {
      final parts = original.map(textParts).toList();
      final count = parts.fold<int>(1, (n, p) => p.length > n ? p.length : n);
      for (var i = 0; i < count; i++) {
        rows.add([
          for (var c = 0; c < parts.length; c++)
            i < parts[c].length
                ? parts[c][i]
                : c == 0
                ? '(Fortsetzung)'
                : '',
        ]);
      }
    }
    if (rows.length == 1)
      rows.add([
        'Keine Einträge',
        for (var i = 1; i < entry.value.first.length; i++) '',
      ]);
    tables[entry.key] = rows;
  }
  String oneLine(Object? value) => '$value'.replaceAll(RegExp(r'\s+'), ' ');
  pw.Widget footer(pw.Context c) => pw.Column(
    children: [
      pw.Divider(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'V${project['version']} | $status | $stamp',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            '${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      pw.Text(
        'Synthetische Symbole. Keine Normprüfung oder Konformitätsaussage.',
        style: const pw.TextStyle(fontSize: 8),
      ),
    ],
  );
  void page(List<pw.Widget> content) => doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: const pw.EdgeInsets.all(30),
      build: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [...content, pw.Spacer(), footer(c)],
      ),
    ),
  );
  page([
    pw.Text(
      'LibreECAD',
      style: pw.TextStyle(fontSize: 16, color: PdfColors.blueGrey),
    ),
    pw.SizedBox(height: 30),
    pw.Text(
      oneLine(project['name']),
      style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 18),
    pw.Text(status, style: pw.TextStyle(fontSize: 18)),
    pw.SizedBox(height: 12),
    pw.Text('Projektversion ${project['version']} | $stamp'),
    pw.SizedBox(height: 24),
    pw.Text(
      'Beschreibung und vollständiges Prüfprotokoll: siehe Inhaltsverzeichnis.',
    ),
    pw.SizedBox(height: 18),
    for (final e in (data['metadata'] as Map).entries)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text('${e.key}: ${oneLine(e.value)}'),
      ),
    if (approval != null) ...[
      pw.SizedBox(height: 18),
      pw.Text(
        'Festgeschrieben durch ${approval['username']} am ${approval['at']}',
      ),
      pw.Text('Begründung und Ausnahmen: siehe Prüfprotokoll.'),
      pw.Text(
        'Begründete Ausnahmen: ${(approval['exceptions'] as Map).length}',
      ),
    ],
  ]);
  final tocCount = (sheets.length + sections.length + 2 + 19) ~/ 20;
  final entries = <String>['1   Deckblatt', '2   Inhaltsverzeichnis'];
  for (var i = 0; i < tocCount; i++) {
    page([]);
  }
  for (final sheet in sheets) {
    entries.add(
      '${doc.document.pdfPageList.pages.length + 1}   Blatt ${sheet['number']} - ${oneLine(sheet['title'])}',
    );
    page([
      pw.Text(
        'Blatt ${sheet['number']} - ${oneLine(sheet['title'])}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SvgImage(
        svg: sheetSvg(d, sheet['id']),
        height: 650,
        customFontLookup: (_, _, _) => regular,
      ),
    ]);
  }
  for (final entry in tables.entries) {
    entries.add('${doc.document.pdfPageList.pages.length + 1}   ${entry.key}');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(30),
        maxPages: 500,
        header: (c) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 18),
          child: pw.Text(entry.key, style: pw.TextStyle(fontSize: 24)),
        ),
        footer: footer,
        build: (c) => [
          pw.TableHelper.fromTextArray(
            data: entry.value,
            cellStyle: pw.TextStyle(font: regular, fontSize: 9),
            headerStyle: pw.TextStyle(font: bold, fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(6),
            cellHeight: 25,
            defaultColumnWidth: const pw.FlexColumnWidth(),
          ),
        ],
      ),
    );
  }
  for (var i = 0; i < tocCount; i++) {
    final subset = entries.skip(i * 20).take(20).toList();
    doc.editPage(
      i + 1,
      pw.Page(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(30),
        build: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Inhaltsverzeichnis', style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 20),
            for (final entry in subset)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(entry, style: const pw.TextStyle(fontSize: 11)),
              ),
            pw.Spacer(),
            footer(c),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
