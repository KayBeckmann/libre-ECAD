import 'dart:convert';
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
      final background = planFor(d, widget.sheetId)?['background'];
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
                        if (background != null) ...[
                          const Positioned.fill(
                            child: ColoredBox(color: Colors.white),
                          ),
                          Positioned(
                            left: (background['x'] as num).toDouble(),
                            top: (background['y'] as num).toDouble(),
                            width: (background['width'] as num).toDouble(),
                            height: (background['height'] as num).toDouble(),
                            child: Image.memory(
                              base64Decode(background['png']),
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                        ],
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
                          if (planFor(d, widget.sheetId)?['kind'] != 'layout')
                            for (final p in instancePorts(d, i))
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
    final plan = planFor(d, sheetId);
    if (plan?['background'] == null) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }
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
      objects(d, 'symbols').isEmpty
          ? 'LibreECAD\nSynthetische Symbole · MIT'
          : 'LibreECAD\nArtikelsymbole im Projektstand',
      const Offset(850, 716),
      size: 12,
    );
    if (plan != null) {
      label(
        c,
        '${planKinds[plan['kind']]} · ${plan['kind'] == 'layout'
            ? '${plan['mmPerUnit']} mm/Einheit'
            : plan['calibration'] == null
            ? 'Maßstab fehlt'
            : 'Maßstab aus Referenzstrecke'}',
        const Offset(56, 680),
        size: 11,
      );
      for (final route in (plan['routes'] as List? ?? []).cast<Json>()) {
        final points = routePoints(d, route),
            path = Path()
              ..moveTo(
                (points.first['x'] as num).toDouble(),
                (points.first['y'] as num).toDouble(),
              );
        for (final point in points.skip(1)) {
          path.lineTo(
            (point['x'] as num).toDouble(),
            (point['y'] as num).toDouble(),
          );
        }
        c.drawPath(
          path,
          Paint()
            ..color = Colors.deepOrange
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke,
        );
        final length = routeLength(d, plan, route)['metres'];
        label(
          c,
          '${route['name']} · ${length == null ? 'Maßstab prüfen' : '${(length as num).toStringAsFixed(2)} m'}',
          Offset(
            (points.first['x'] as num).toDouble() + 10,
            (points.first['y'] as num).toDouble() + 20,
          ),
          size: 11,
        );
      }
    }
    for (final w in objects(
      d,
      'wires',
    ).where((w) => w['sheetId'] == sheetId && plan?['kind'] != 'layout')) {
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
      if (w['conductor'] != null) {
        label(c, w['conductor'], points[1] + const Offset(6, -30), size: 12);
      }
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
      if (plan?['kind'] == 'layout') {
        final box = layoutRectangle(d, plan!, i);
        if (box == null) {
          label(c, '${device['bmk']} · Maße fehlen', Offset(x, y));
        } else {
          c.drawRect(
            Rect.fromLTWH(
              (box['x'] as num).toDouble(),
              (box['y'] as num).toDouble(),
              (box['width'] as num).toDouble(),
              (box['height'] as num).toDouble(),
            ),
            line,
          );
          label(
            c,
            '${device['bmk']}\n${device['article']['widthMm']} × ${device['article']['heightMm']} mm',
            Offset(x, y),
            size: 10,
          );
        }
        continue;
      }
      final symbol = symbolByKey(i['symbol'], d);
      for (final shape in symbolGeometry(symbol)) {
        final a = Offset(
          x + (shape['x'] as num).toDouble(),
          y + (shape['y'] as num).toDouble(),
        );
        switch (shape['kind']) {
          case 'line':
            c.drawLine(
              a,
              Offset(
                x + (shape['x2'] as num).toDouble(),
                y + (shape['y2'] as num).toDouble(),
              ),
              line,
            );
          case 'rect':
            c.drawRect(
              Rect.fromPoints(
                a,
                Offset(
                  x + (shape['x2'] as num).toDouble(),
                  y + (shape['y2'] as num).toDouble(),
                ),
              ),
              line,
            );
          case 'circle':
            c.drawCircle(a, (shape['radius'] as num).toDouble(), line);
          case 'text':
            label(c, shape['text'], a, size: 12);
        }
      }
      final labelX =
          x +
          (symbol.definition != null ||
                  ['Drehstrom', 'Automatisierung'].contains(symbol.group)
              ? 140
              : 32);
      label(c, '${device['bmk']}', Offset(labelX, y - 20), size: 14);
      label(c, '${device['label']}', Offset(labelX, y), size: 10);
      final refs = crossReferences(d, device['id'])
          .where((r) => r['instanceId'] != i['id'])
          .map((r) => r['position'])
          .join(', ');
      if (refs.isNotEmpty) {
        label(c, 'Ref. $refs', Offset(labelX, y + 17), size: 10, color: accent);
      }
      for (final p in instancePorts(d, i)) {
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
