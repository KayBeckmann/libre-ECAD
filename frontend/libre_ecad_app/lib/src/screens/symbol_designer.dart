import 'dart:math' as math;

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

class SymbolDesigner extends StatefulWidget {
  const SymbolDesigner({super.key, this.initial, this.editable = true});
  final Json? initial;
  final bool editable;
  @override
  State<SymbolDesigner> createState() => _SymbolDesignerState();
}

class _SymbolDesignerState extends State<SymbolDesigner> {
  late Json data = widget.initial == null
      ? symbolTemplate('switch', newId())
      : cloneJson(widget.initial!);
  late final name = TextEditingController(text: data['name']),
      code = TextEditingController(text: data['code']);
  final pin = TextEditingController(text: '1'),
      label = TextEditingController(text: '1');
  final undo = <Json>[], redo = <Json>[];
  String tool = 'select';
  String? error, selection;
  Offset? start;
  bool get enabled =>
      widget.editable &&
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.sizeOf(context).height -
              kToolbarHeight -
              MediaQuery.paddingOf(context).vertical >=
          500;
  @override
  void dispose() {
    for (final c in [name, code, pin, label]) {
      c.dispose();
    }
    super.dispose();
  }

  void change(void Function(Json) edit) {
    if (!enabled) return;
    final previous = cloneJson(data)
      ..['name'] = name.text
      ..['code'] = code.text;
    final next = cloneJson(previous);
    edit(next);
    setState(() {
      undo.add(previous);
      if (undo.length > 60) undo.removeAt(0);
      redo.clear();
      data = next;
      error = null;
    });
  }

  void history(bool back) {
    if (!enabled) return;
    final from = back ? undo : redo, to = back ? redo : undo;
    if (from.isEmpty) return;
    setState(() {
      to.add(
        cloneJson(data)
          ..['name'] = name.text
          ..['code'] = code.text,
      );
      data = from.removeLast();
      name.text = data['name'];
      code.text = data['code'];
      selection = null;
    });
  }

  Offset point(Offset p, Size size) {
    final scale = math.min(size.width / 280, size.height / 280);
    return Offset(
      ((p.dx - size.width / 2) / scale / 10).round() * 10.0,
      ((p.dy - size.height / 2) / scale / 10).round() * 10.0,
    );
  }

  void finish(Offset end) {
    if (!enabled || start == null) return;
    final a = start!;
    start = null;
    if (a.dx.abs() > 120 ||
        a.dy.abs() > 120 ||
        end.dx.abs() > 120 ||
        end.dy.abs() > 120) {
      return;
    }
    if (tool == 'select') {
      if (selection == null) return;
      final parts = selection!.split(':');
      final index = int.parse(parts[1]);
      change((d) {
        final p = d[parts[0]][index] as Json;
        final delta = end - a;
        p['x'] += delta.dx;
        p['y'] += delta.dy;
        if (p.containsKey('x2')) {
          p['x2'] += delta.dx;
          p['y2'] += delta.dy;
        }
      });
    } else if (tool == 'pin') {
      change(
        (d) => (d['ports'] as List).add({
          'id': pin.text.trim(),
          'label': label.text.trim(),
          'x': end.dx,
          'y': end.dy,
        }),
      );
    } else if (tool == 'text') {
      change(
        (d) => (d['primitives'] as List).add({
          'kind': 'text',
          'x': end.dx,
          'y': end.dy,
          'text': label.text.trim(),
        }),
      );
    } else if (a != end) {
      change(
        (d) => (d['primitives'] as List).add({
          'kind': tool,
          'x': a.dx,
          'y': a.dy,
          if (tool == 'circle')
            'radius': ((end - a).distance / 10).round() * 10
          else ...{
            'x2': end.dx,
            'y2': end.dy,
          },
        }),
      );
    }
  }

  Future<void> template(String key) async {
    if (!enabled) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vorlage übernehmen?'),
        content: const Text(
          'Die aktuelle Geometrie wird ersetzt. Rückgängig bleibt möglich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Vorlage laden'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    change((d) {
      d.clear();
      d.addAll(symbolTemplate(key, data['id']));
    });
    name.text = data['name'];
    code.text = data['code'];
    selection = null;
  }

  void save() {
    if (!enabled) return;
    try {
      final next = cloneJson(data)
        ..['name'] = name.text.trim()
        ..['code'] = code.text.trim();
      validateSymbol(next);
      Navigator.pop(context, next);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Widget canvas() => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        key: const ValueKey('symbol-designer-canvas'),
        behavior: HitTestBehavior.opaque,
        onPanStart: enabled
            ? (e) => _last = start = point(e.localPosition, size)
            : null,
        onPanEnd: enabled
            ? (_) {
                if (_last != null) finish(_last!);
              }
            : null,
        onPanUpdate: enabled
            ? (e) => _last = point(e.localPosition, size)
            : null,
        onTapUp: enabled
            ? (e) {
                start = point(e.localPosition, size);
                finish(start!);
              }
            : null,
        child: CustomPaint(
          painter: _SymbolPainter(data, selection),
          size: Size.infinite,
        ),
      );
    },
  );
  Offset? _last;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Schaltsymbol zeichnen'),
      actions: [
        IconButton(
          tooltip: 'Rückgängig',
          onPressed: enabled && undo.isNotEmpty ? () => history(true) : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Wiederholen',
          onPressed: enabled && redo.isNotEmpty ? () => history(false) : null,
          icon: const Icon(Icons.redo),
        ),
        TextButton(
          onPressed: enabled ? save : null,
          child: const Text('Symbol übernehmen'),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 1000 || c.maxHeight < 500;
        return Column(
          children: [
            if (compact)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Darstellung zu klein für Bearbeitung · mindestens 1000 × 500 im Arbeitsbereich.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (!compact)
                    SizedBox(
                      width: 260,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          TextField(
                            controller: name,
                            readOnly: !enabled,
                            decoration: const InputDecoration(
                              labelText: 'Symbolname',
                            ),
                            maxLength: 100,
                          ),
                          TextField(
                            controller: code,
                            readOnly: !enabled,
                            decoration: const InputDecoration(
                              labelText: 'BMK-Kennbuchstaben',
                            ),
                            maxLength: 4,
                          ),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: data['role'],
                            key: ValueKey(data['role']),
                            decoration: const InputDecoration(
                              labelText: 'Funktion',
                            ),
                            items: [
                              for (final e in {
                                'generic': 'Allgemeines Gerät',
                                'coil': 'Relaisspule · A1/A2',
                                'no': 'Schließer · 13/14',
                                'nc': 'Öffner · 21/22',
                              }.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: enabled
                                ? (v) => change((d) {
                                    d['role'] = v;
                                    if (v != 'generic') code.text = 'K';
                                  })
                                : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('Mit Vorlage beginnen'),
                            items: [
                              for (final s in symbolLibrary)
                                DropdownMenuItem(
                                  value: s.key,
                                  child: Text(
                                    s.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: enabled ? (v) => template(v!) : null,
                          ),
                          const Divider(),
                          for (final e in {
                            'select': 'Auswahl verschieben',
                            'line': 'Linie',
                            'rect': 'Rechteck',
                            'circle': 'Kreis',
                            'text': 'Text',
                            'pin': 'Anschlusspunkt',
                          }.entries)
                            ListTile(
                              title: Text(e.value),
                              selected: tool == e.key,
                              leading: Icon(
                                tool == e.key
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                              ),
                              onTap: enabled
                                  ? () => setState(() => tool = e.key)
                                  : null,
                              dense: true,
                            ),
                          TextField(
                            controller: pin,
                            readOnly: !enabled,
                            decoration: const InputDecoration(
                              labelText: 'Anschluss-ID',
                            ),
                            maxLength: 40,
                          ),
                          TextField(
                            controller: label,
                            readOnly: !enabled,
                            decoration: const InputDecoration(
                              labelText: 'Beschriftung / Text',
                            ),
                            maxLength: 40,
                          ),
                          const Text(
                            'Linie, Rechteck und Kreis ziehen. Anschlüsse/Text per Klick setzen. Zum Verschieben rechts ein Element wählen und im Raster ziehen. Raster: 10; Bereich: ±120.',
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: canvas()),
                  if (!compact)
                    SizedBox(
                      width: 230,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          const Text(
                            'ELEMENTE',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final kind in ['ports', 'primitives'])
                            for (
                              var n = 0;
                              n < (data[kind] as List).length;
                              n++
                            )
                              ListTile(
                                dense: true,
                                selected: selection == '$kind:$n',
                                title: Text(
                                  kind == 'ports'
                                      ? 'Anschluss ${data[kind][n]['id']}'
                                      : '${data[kind][n]['kind']} ${n + 1}',
                                ),
                                subtitle: Text(
                                  '${data[kind][n]['x']} / ${data[kind][n]['y']}',
                                ),
                                onTap: () => setState(() {
                                  selection = '$kind:$n';
                                  tool = 'select';
                                }),
                                trailing: IconButton(
                                  tooltip: 'Element entfernen',
                                  onPressed: enabled
                                      ? () {
                                          change(
                                            (d) =>
                                                (d[kind] as List).removeAt(n),
                                          );
                                          selection = null;
                                        }
                                      : null,
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.data, this.selection);
  final Json data;
  final String? selection;
  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xfff5f8f8));
    final scale = math.min(size.width / 280, size.height / 280);
    c.save();
    c.translate(size.width / 2, size.height / 2);
    c.scale(scale);
    for (double x = -120; x <= 120; x += 10) {
      for (double y = -120; y <= 120; y += 10) {
        c.drawCircle(
          Offset(x, y),
          .6,
          Paint()..color = const Color(0xffb9c9cb),
        );
      }
    }
    void text(String value, Offset p) {
      final t = TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(color: Color(0xff203d4c), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 180);
      t.paint(c, p);
    }

    for (var n = 0; n < (data['primitives'] as List).length; n++) {
      final s = data['primitives'][n] as Json;
      final p = Offset((s['x'] as num).toDouble(), (s['y'] as num).toDouble()),
          line = Paint()
            ..color = (selection == 'primitives:$n'
                ? Colors.orange
                : const Color(0xff203d4c))
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
      switch (s['kind']) {
        case 'line':
          c.drawLine(
            p,
            Offset((s['x2'] as num).toDouble(), (s['y2'] as num).toDouble()),
            line,
          );
        case 'rect':
          c.drawRect(
            Rect.fromPoints(
              p,
              Offset((s['x2'] as num).toDouble(), (s['y2'] as num).toDouble()),
            ),
            line,
          );
        case 'circle':
          c.drawCircle(p, (s['radius'] as num).toDouble(), line);
        case 'text':
          text(s['text'], p);
      }
    }
    for (final p in data['ports'] as List) {
      final o = Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
      c.drawCircle(o, 3, Paint()..color = const Color(0xff137c76));
      text('${p['id']} · ${p['label']}', o + const Offset(5, -12));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _SymbolPainter old) =>
      old.data != data || old.selection != selection;
}
