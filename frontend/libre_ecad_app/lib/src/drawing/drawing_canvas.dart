import 'dart:math' as math;

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

String shortObjectId(Object? value) {
  final text = value.toString();
  return text.length > 6 ? text.substring(0, 6) : text;
}

const ink = Color(0xff203d4c);
const accent = Color(0xff137c76);
Offset endpointOffset(Json d, Json ref) {
  final p = endpointPosition(d, ref);
  return Offset(p.x, p.y);
}

List<Offset> wireRoute(Json d, Json wire) {
  final a = endpointOffset(d, wire['from']), b = endpointOffset(d, wire['to']);
  // Stable orthogonal route. No electrical meaning is attached to its bends.
  final midY = ((a.dy + b.dy) / 40).round() * 20.0;
  return [a, Offset(a.dx, midY), Offset(b.dx, midY), b];
}

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.drawing,
    required this.sheetId,
    required this.projectName,
    required this.version,
    required this.selected,
    required this.editable,
    required this.onTap,
    required this.onSelect,
    required this.onMove,
    required this.onPort,
    this.pending,
  });
  final Json drawing;
  final String sheetId, projectName;
  final int version;
  final String? selected;
  final Json? pending;
  final bool editable;
  final void Function(Offset) onTap;
  final void Function(String) onSelect;
  final void Function(String, Offset) onMove;
  final void Function(Json) onPort;
  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  final transform = TransformationController();
  bool fitted = false;
  Offset? dragStart, dragDelta;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final fit = math
          .min(c.maxWidth / 1240, c.maxHeight / 840)
          .clamp(0.2, 1.0);
      if (!fitted) {
        fitted = true;
        transform.value = Matrix4.diagonal3Values(fit, fit, 1);
      }
      final d = widget.drawing;
      return Stack(
        children: [
          ColoredBox(
            color: const Color(0xffdfe6e8),
            child: InteractiveViewer(
              transformationController: transform,
              constrained: false,
              minScale: 0.2,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(600),
              panEnabled: !widget.editable,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: widget.editable
                      ? (e) => widget.onTap(e.localPosition)
                      : null,
                  child: SizedBox(
                    width: 1200,
                    height: 800,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: SheetPainter(
                              d,
                              widget.sheetId,
                              widget.projectName,
                              widget.version,
                              widget.selected,
                            ),
                          ),
                        ),
                        for (final i in objects(
                          d,
                          'instances',
                        ).where((i) => i['sheetId'] == widget.sheetId))
                          Positioned(
                            left: (i['x'] as num).toDouble() - 48,
                            top: (i['y'] as num).toDouble() - 24,
                            width: 96,
                            height: 48,
                            child: Semantics(
                              button: true,
                              identifier: 'ecad-hit-symbol-${i['id']}',
                              label:
                                  'Symbol ${objectById(d, 'devices', i['deviceId'])['bmk']}',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.onSelect(i['id']),
                                onPanStart: widget.editable
                                    ? (_) {
                                        dragStart = Offset(
                                          (i['x'] as num).toDouble(),
                                          (i['y'] as num).toDouble(),
                                        );
                                        dragDelta = Offset.zero;
                                        widget.onSelect(i['id']);
                                      }
                                    : null,
                                onPanUpdate: widget.editable
                                    ? (e) {
                                        dragDelta = dragDelta! + e.delta;
                                      }
                                    : null,
                                onPanEnd: widget.editable
                                    ? (_) {
                                        widget.onMove(
                                          i['id'],
                                          dragStart! + dragDelta!,
                                        );
                                      }
                                    : null,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        for (final i in objects(
                          d,
                          'instances',
                        ).where((i) => i['sheetId'] == widget.sheetId))
                          for (final p in symbolByKey(i['symbol']).ports)
                            port(
                              d,
                              portRef(i['id'], p),
                              '${objectById(d, 'devices', i['deviceId'])['bmk']}:$p',
                            ),
                        for (final kind in ['nodes', 'continuations'])
                          for (final o in objects(
                            d,
                            kind,
                          ).where((o) => o['sheetId'] == widget.sheetId))
                            port(
                              d,
                              pointRef(
                                kind == 'nodes' ? 'node' : 'continuation',
                                o['id'],
                              ),
                              kind == 'nodes'
                                  ? 'Knoten ${shortObjectId(o['id'])}'
                                  : 'Fortsetzung ${o['label']}',
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 2,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Verkleinern',
                    onPressed: () => zoom(0.8),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: 'Blatt einpassen',
                    onPressed: () => setState(() => fitted = false),
                    icon: const Icon(Icons.fit_screen),
                  ),
                  IconButton(
                    tooltip: 'Vergrößern',
                    onPressed: () => zoom(1.25),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  void zoom(double factor) {
    final current = transform.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(0.2, 3.0);
    transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  Widget port(Json d, Json ref, String label) {
    final p = endpointOffset(d, ref);
    final active =
        widget.pending != null &&
        endpointKey(d, ref) == endpointKey(d, widget.pending!);
    return Positioned(
      left: p.dx - 11,
      top: p.dy - 11,
      width: 22,
      height: 22,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          identifier:
              'ecad-hit-port-${ref['kind']}-${ref['instanceId'] ?? ref['id']}-${ref['terminalId'] ?? ''}',
          label: 'Anschluss $label',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.editable ? () => widget.onPort(ref) : null,
            child: Center(
              child: Container(
                width: active ? 12 : 7,
                height: active ? 12 : 7,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.orange
                      : ref['kind'] == 'node'
                      ? accent
                      : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SheetPainter extends CustomPainter {
  SheetPainter(this.d, this.sheetId, this.name, this.version, this.selected);
  final Json d;
  final String sheetId, name;
  final int version;
  final String? selected;
  void label(
    Canvas c,
    String value,
    Offset p, {
    double size = 12,
    Color color = ink,
  }) {
    final t = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontFamily: 'monospace', fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 330);
    t.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grid = Paint()
      ..color = const Color(0xffdce7e9)
      ..strokeWidth = 1;
    for (double x = 60; x < 1160; x += 20) {
      for (double y = 80; y < 700; y += 20) {
        c.drawCircle(Offset(x, y), 0.7, grid);
      }
    }
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    c.drawRect(const Rect.fromLTWH(40, 60, 1120, 640), line);
    c.drawRect(const Rect.fromLTWH(40, 700, 1120, 60), line);
    for (var i = 0; i < 10; i++) {
      label(c, '${i + 1}', Offset(88 + i * 112.0, 38));
    }
    for (var i = 0; i < 6; i++) {
      label(c, String.fromCharCode(65 + i), Offset(18, 100 + i * 100.0));
    }
    final sheet = objectById(d, 'sheets', sheetId);
    label(
      c,
      '${sheet['number']}  /  ${objects(d, 'sheets').length}    ${sheet['title']}',
      const Offset(56, 712),
      size: 16,
    );
    label(
      c,
      '$name · Arbeitsstand $version · nicht fachlich freigegeben',
      const Offset(56, 740),
      size: 11,
    );
    label(
      c,
      'LibreECAD / M4\nSynthetische Symbole · MIT',
      const Offset(850, 716),
      size: 12,
    );
    for (final w in objects(d, 'wires').where((w) => w['sheetId'] == sheetId)) {
      final points = wireRoute(d, w);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      c.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      if (w['cableId'] != null) {
        final cable = objectById(d, 'cables', w['cableId']);
        final core = (cable['cores'] as List).firstWhere(
          (o) => o['id'] == w['coreId'],
        );
        label(
          c,
          '${cable['bmk']}:${core['label']}',
          points[1] + const Offset(6, -16),
          size: 10,
        );
      }
    }
    for (final i in objects(
      d,
      'instances',
    ).where((i) => i['sheetId'] == sheetId)) {
      final x = (i['x'] as num).toDouble(), y = (i['y'] as num).toDouble();
      final device = objectById(d, 'devices', i['deviceId']);
      if (i['id'] == selected) {
        c.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 110, height: 100),
          Paint()..color = accent.withValues(alpha: 0.09),
        );
      }
      final symbol = symbolByKey(i['symbol']);
      if (symbol.key == 'terminal') {
        c.drawCircle(Offset(x, y), 8, line);
        c.drawLine(Offset(x - 5, y), Offset(x + 5, y), line);
      } else if (symbol.key == 'motor') {
        c.drawCircle(Offset(x, y), 24, line);
        label(c, 'M', Offset(x - 8, y - 12), size: 20);
        for (final p in symbol.ports) {
          final pos = endpointOffset(d, portRef(i['id'], p));
          c.drawLine(pos, Offset(pos.dx, y - 24), line);
        }
      } else {
        final top = Offset(x, y - 40), bottom = Offset(x, y + 40);
        c.drawLine(top, Offset(x, y - 18), line);
        c.drawLine(Offset(x, y + 18), bottom, line);
        if (symbol.key == 'switch' || symbol.key == 'contact') {
          c.drawLine(Offset(x, y + 18), Offset(x + 20, y - 18), line);
          c.drawCircle(Offset(x, y - 18), 2, line);
          c.drawCircle(Offset(x, y + 18), 2, line);
        } else {
          c.drawRect(
            Rect.fromCenter(center: Offset(x, y), width: 44, height: 36),
            line,
          );
          label(
            c,
            symbol.key == 'coil'
                ? 'K'
                : symbol.key == 'breaker'
                ? 'Q'
                : 'G',
            Offset(x - 7, y - 9),
            size: 14,
          );
        }
      }
      label(c, '${device['bmk']}', Offset(x + 32, y - 20), size: 14);
      label(c, '${device['label']}', Offset(x + 32, y), size: 10);
      final refs = crossReferences(d, device['id'])
          .where((r) => r['instanceId'] != i['id'])
          .map((r) => r['position'])
          .join(', ');
      if (refs.isNotEmpty) {
        label(c, 'Ref. $refs', Offset(x + 32, y + 17), size: 10, color: accent);
      }
      for (final p in symbol.ports) {
        final pos = endpointOffset(d, portRef(i['id'], p));
        final t = (device['terminals'] as List).firstWhere((t) => t['id'] == p);
        label(c, '${t['label']}', pos + const Offset(-26, -12), size: 10);
      }
    }
    for (final n in objects(d, 'nodes').where((n) => n['sheetId'] == sheetId)) {
      c.drawCircle(
        Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble()),
        5,
        Paint()..color = accent,
      );
    }
    for (final o in objects(
      d,
      'continuations',
    ).where((o) => o['sheetId'] == sheetId)) {
      final p = Offset((o['x'] as num).toDouble(), (o['y'] as num).toDouble());
      final other = objects(
        d,
        'continuations',
      ).firstWhere((v) => v['linkId'] == o['linkId'] && v['id'] != o['id']);
      c.drawPath(
        Path()
          ..moveTo(p.dx - 10, p.dy - 9)
          ..lineTo(p.dx + 10, p.dy)
          ..lineTo(p.dx - 10, p.dy + 9),
        line,
      );
      label(
        c,
        '${o['label']} -> ${positionReference(d, other)}',
        p + const Offset(16, -8),
        size: 11,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SheetPainter old) => true;
}
