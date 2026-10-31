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

List<Offset> wireRoute(Json d, Json wire) => [
  for (final point in routedWirePoints(d, wire)) Offset(point.x, point.y),
];

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
    this.selectingRegion = false,
    this.region,
    this.onRegion,
    this.panning = false,
    this.onWireSegment,
  });
  final bool selectingRegion;
  final bool panning;
  final void Function(String, int, Offset)? onWireSegment;
  final Rect? region;
  final ValueChanged<Rect>? onRegion;
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
  Offset? dragStart, dragDelta, regionStart;
  Rect? regionDrag;
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
              panEnabled: widget.panning || !widget.editable,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: widget.editable && widget.selectingRegion
                      ? (event) => setState(() {
                          regionStart = event.localPosition;
                          regionDrag = Rect.fromPoints(
                            regionStart!,
                            regionStart!,
                          );
                        })
                      : null,
                  onPanUpdate: widget.editable && widget.selectingRegion
                      ? (event) => setState(() {
                          regionDrag = Rect.fromPoints(
                            regionStart!,
                            event.localPosition,
                          );
                        })
                      : null,
                  onPanEnd: widget.editable && widget.selectingRegion
                      ? (_) {
                          if (regionDrag != null) {
                            widget.onRegion?.call(regionDrag!);
                          }
                          setState(() {
                            regionDrag = null;
                            regionStart = null;
                          });
                        }
                      : null,
                  onPanCancel: widget.selectingRegion
                      ? () => setState(() {
                          regionDrag = null;
                          regionStart = null;
                        })
                      : null,
                  onTapUp: widget.editable && !widget.selectingRegion && !widget.panning
                      ? (e) => widget.onTap(e.localPosition)
                      : null,
                  child: SizedBox(
                    width: 1200,
                    height: 800,
                    child: IgnorePointer(
                      ignoring: widget.selectingRegion || widget.panning,
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
                          if (widget.editable && widget.onWireSegment != null)
                            for (final w in objects(d, 'wires').where((w) => w['sheetId'] == widget.sheetId))
                              for (var n = 0; n < wireRoute(d, w).length - 1; n++)
                                wireHandle(d, w, n),
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
                          if ((regionDrag ?? widget.region) != null)
                            Positioned.fromRect(
                              rect: regionDrag ?? widget.region!,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: .12),
                                    border: Border.all(color: accent, width: 2),
                                  ),
                                ),
                              ),
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

  Widget wireHandle(Json d, Json wire, int segment) {
    final route = wireRoute(d, wire);
    final a = route[segment], b = route[segment + 1];
    final center = (a + b) / 2;
    if ((a - b).distance < 24) return const SizedBox.shrink();
    Offset delta = Offset.zero;
    return Positioned(
      left: center.dx - 10,
      top: center.dy - 10,
      width: 20,
      height: 20,
      child: Semantics(
        button: true,
        identifier: 'ecad-hit-wire-${wire['id']}-$segment',
        label: 'Leitungssegment verschieben',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => delta = Offset.zero,
          onPanUpdate: (e) => delta += e.delta / transform.value.getMaxScaleOnAxis(),
          onPanEnd: (_) => widget.onWireSegment?.call(
            wire['id'], segment, center + delta,
          ),
          child: Center(child: Container(width: 7, height: 7,
            decoration: const BoxDecoration(color: accent, shape: BoxShape.circle))),
        ),
      ),
    );
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

/// Only persisted sheet data and the supplied project revision appear in the block.
class SheetTitleBlockData {
  SheetTitleBlockData.fromDrawing(
    Json drawing,
    String sheetId,
    this.project,
    int version,
  ) : title = objectById(drawing, 'sheets', sheetId)['title'].toString(),
      sheet =
          '${objectById(drawing, 'sheets', sheetId)['number']} / ${objects(drawing, 'sheets').length}',
      status = 'Arbeitsstand $version',
      revisionRows = _rows(objectById(drawing, 'sheets', sheetId));

  final String title, project, sheet, status;
  final List<String> revisionRows;
  final String warning = 'Nicht fachlich freigegeben';

  static List<String> _rows(Json sheet) {
    final revisions = (sheet['revisions'] as List? ?? []).cast<Json>();
    if (revisions.isEmpty) return ['Keine Revisionen erfasst'];
    return revisions.reversed.take(4).map((entry) {
      final note = entry['note'];
      return '${entry['revision']}  ${entry['date']}${note == null ? '' : '  $note'}';
    }).toList();
  }

  @override
  String toString() => '$title · $project · $sheet · $status · $warning';
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

  void blockText(
    Canvas c,
    String text,
    Rect bounds, {
    double size = 12,
    bool bold = false,
    Color color = ink,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: bounds.width);
    c.save();
    c.clipRect(bounds);
    painter.paint(c, bounds.topLeft);
    c.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    final plan = planFor(d, sheetId);
    if (plan?['background'] == null) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }
    // A background plan stays visible in the original (40,60)–(1160,700)
    // drawing field; its margins are reserved for the sheet furniture.
    final paper = Paint()..color = Colors.white;
    c.drawRect(const Rect.fromLTWH(0, 0, 1200, 60), paper);
    c.drawRect(const Rect.fromLTWH(0, 60, 40, 640), paper);
    c.drawRect(const Rect.fromLTWH(1160, 60, 40, 640), paper);
    c.drawRect(const Rect.fromLTWH(0, 700, 1200, 100), paper);
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
    // Zone boundaries coincide with positionReference/columnFor: no change
    // to drawing coordinates, routing or hit targets.
    c.drawRect(const Rect.fromLTWH(12, 20, 1176, 760), line);
    c.drawRect(const Rect.fromLTWH(40, 60, 1120, 640), line);
    c.drawLine(const Offset(40, 20), const Offset(40, 700), line);
    c.drawLine(const Offset(1160, 20), const Offset(1160, 700), line);
    for (var i = 1; i < 10; i++) {
      final x = 40 + i * 112.0;
      c.drawLine(Offset(x, 20), Offset(x, 60), line);
    }
    for (var i = 1; i < 6; i++) {
      final y = 60 + i * 100.0;
      c.drawLine(Offset(12, y), Offset(40, y), line);
    }
    c.drawLine(const Offset(12, 700), const Offset(1188, 700), line);
    c.drawLine(const Offset(440, 700), const Offset(440, 780), line);
    c.drawLine(const Offset(850, 700), const Offset(850, 780), line);
    for (var i = 0; i < 10; i++) {
      blockText(c, '${i + 1}', Rect.fromLTWH(88 + i * 112.0, 33, 30, 20));
    }
    for (var i = 0; i < 6; i++) {
      blockText(
        c,
        String.fromCharCode(65 + i),
        Rect.fromLTWH(20, 100 + i * 100.0, 18, 20),
      );
    }
    final block = SheetTitleBlockData.fromDrawing(d, sheetId, name, version);
    blockText(
      c,
      'REVISION / DATUM / NOTIZ',
      const Rect.fromLTWH(28, 705, 395, 15),
      size: 10,
    );
    for (var i = 0; i < block.revisionRows.length; i++) {
      blockText(
        c,
        block.revisionRows[i],
        Rect.fromLTWH(28, 721 + i * 14.0, 395, 14),
        size: 10,
      );
    }
    blockText(c, 'ZEICHNUNG', const Rect.fromLTWH(456, 708, 378, 18), size: 10);
    blockText(
      c,
      block.title,
      const Rect.fromLTWH(456, 732, 378, 32),
      size: 21,
      bold: true,
    );
    blockText(c, 'PROJEKT', const Rect.fromLTWH(866, 708, 306, 18), size: 10);
    blockText(
      c,
      block.project,
      const Rect.fromLTWH(866, 722, 306, 20),
      size: 14,
      bold: true,
    );
    blockText(
      c,
      'BLATT ${block.sheet} · ${block.status}',
      const Rect.fromLTWH(866, 742, 306, 18),
      size: 11,
    );
    blockText(
      c,
      block.warning,
      const Rect.fromLTWH(866, 760, 306, 16),
      size: 11,
      bold: true,
      color: const Color(0xffa33e27),
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
      c.save();
      c.translate(x, y);
      c.rotate((i['rotation'] as num? ?? 0) * math.pi / 180);
      c.translate(-x, -y);
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
      c.restore();
      final labelX =
          x +
          (symbol.definition != null ||
                  ['Drehstrom', 'Automatisierung'].contains(symbol.group)
              ? 140
              : 32);
      label(c, terminalDisplayBmk(d, device), Offset(labelX, y - 20), size: 14);
      label(c, '${device['label']}', Offset(labelX, y), size: 10);
      final refs = instanceReferences(
        d,
        i,
      ).map((r) => r['position']).join(', ');
      if (refs.isNotEmpty && symbol.role != 'coil') {
        label(c, 'Ref. $refs', Offset(labelX, y + 17), size: 10, color: accent);
      }
      final comb = relayContactComb(d, i);
      if (comb.isNotEmpty) {
        label(
          c,
          'Kontaktkamm',
          Offset((comb.first['x'] as num).toDouble() - 16, y + 42),
          size: 10,
        );
      }
      for (final contact in comb) {
        final cx = (contact['x'] as num).toDouble(),
            cy = (contact['y'] as num).toDouble();
        // Mirror the SVG/PDF comb: NO has an air gap, NC touches its terminal.
        final nc = contact['role'] == 'nc';
        c.drawLine(
          Offset(nc ? cx + 8 : cx, cy - 15),
          Offset(nc ? cx + 8 : cx, cy - 8),
          line,
        );
        c.drawLine(Offset(cx, cy + 8), Offset(cx, cy + 15), line);
        c.drawLine(
          Offset(cx, cy + 8),
          Offset(cx + 8, nc ? cy - 8 : cy - 3),
          line,
        );
        label(
          c,
          contact['terminals'].join('/'),
          Offset(cx + 18, cy - 18),
          size: 10,
        );
        label(
          c,
          contact['role'] == 'nc' ? 'Öffner' : 'Schließer',
          Offset(cx + 18, cy - 3),
          size: 9,
        );
        label(
          c,
          contact['position'],
          Offset(cx - 14, cy + 22),
          size: 10,
          color: accent,
        );
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
