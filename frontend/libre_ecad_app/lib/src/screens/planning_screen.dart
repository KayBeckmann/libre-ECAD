import 'dart:convert';
import 'dart:math' as math;

import 'package:ecad_core/ecad_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../drawing/drawing_canvas.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({
    super.key,
    required this.drawing,
    required this.sheetId,
    required this.editable,
  });
  final Json drawing;
  final String sheetId;
  final bool editable;
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  late Json d = cloneJson(widget.drawing);
  late Json plan =
      planFor(d, widget.sheetId) ??
      {
        'id': widget.sheetId,
        'kind': 'installation',
        'circuits': <Json>[],
        'routes': <Json>[],
      };
  String? error, selected;
  bool measuring = false, routing = false;
  final points = <Json>[];
  bool get enabled =>
      widget.editable &&
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.sizeOf(context).height -
              kToolbarHeight -
              MediaQuery.paddingOf(context).vertical >=
          500;
  @override
  void initState() {
    super.initState();
    if (planFor(d, widget.sheetId) == null) {
      (d.putIfAbsent('plans', () => []) as List).add(plan);
    }
  }

  void change(void Function() action) {
    if (!enabled) return;
    final previous = cloneJson(d);
    setState(() {
      try {
        action();
        validateDrawing(d);
        error = null;
      } catch (e) {
        d = previous;
        plan = planFor(d, widget.sheetId)!;
        error = '$e';
      }
    });
  }

  Future<Map<String, String>?> fields(
    String title,
    Map<String, String> values,
  ) async {
    final controls = {
      for (final e in values.entries)
        e.key: TextEditingController(text: e.value),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in controls.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(labelText: e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, {
              for (final e in controls.entries) e.key: e.value.text.trim(),
            }),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    // Controllers remain alive through the dialog's exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controls.values) {
      c.dispose();
    }
    return result;
  }

  Future<void> background() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (file == null || !mounted || !enabled) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 8000000) {
        throw const FormatException(
          'Vorlage maximal 8 MB; bitte vorher verkleinern.',
        );
      }
      final decoder = img.findDecoderForData(bytes),
          info = decoder?.startDecode(bytes);
      if (info == null || info.width * info.height > 16000000) {
        throw const FormatException(
          'Bild nicht lesbar oder über 16 Megapixel.',
        );
      }
      final decoded = decoder!.decodeFrame(0);
      if (decoded == null) throw const FormatException('Bild nicht lesbar.');
      final factor = math.min(
        1,
        1600 / math.max(decoded.width, decoded.height),
      );
      final image = img.copyResize(
        decoded,
        width: (decoded.width * factor).round(),
        height: (decoded.height * factor).round(),
      );
      final png = base64Encode(img.encodePng(image));
      if (png.length > 2800000) {
        throw const FormatException(
          'Komprimierte Vorlage zu groß; bitte vereinfachen.',
        );
      }
      final meta = await fields('Bildherkunft', {
        'Quelle / Nutzungsrecht': file.name,
        'Revision': '1',
      });
      if (meta == null || !mounted || !enabled) return;
      final scale = math.min(1120 / image.width, 640 / image.height);
      change(() {
        plan['background'] = {
          'png': png,
          'origin': meta['Quelle / Nutzungsrecht'],
          'revision': meta['Revision'],
          'locked': true,
          'x': 40,
          'y': 60,
          'width': image.width * scale,
          'height': image.height * scale,
        };
        plan.remove('calibration');
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> alignBackground() async {
    final b = plan['background'];
    if (b == null || b['locked'] == true) return;
    final values = await fields('Vorlage ausrichten', {
      'X': '${b['x']}',
      'Y': '${b['y']}',
      'Breite': '${b['width']}',
      'Höhe': '${b['height']}',
    });
    if (values == null || !mounted) return;
    change(() {
      for (final e in {
        'X': 'x',
        'Y': 'y',
        'Breite': 'width',
        'Höhe': 'height',
      }.entries) {
        b[e.value] = num.tryParse(values[e.key]!);
      }
      plan.remove('calibration');
    });
  }

  Future<void> tap(Offset at) async {
    if (!enabled) return;
    final p = <String, dynamic>{
      'x': at.dx.clamp(0, 1200),
      'y': at.dy.clamp(0, 800),
    };
    if (measuring) {
      setState(() => points.add(p));
      if (points.length == 2) {
        final values = await fields('Referenzstrecke', {
          'Reale Länge [m]': '',
          'Quelle / Bezug': '',
          'Perspektive geprüft (ja/nein)': 'nein',
        });
        if (!mounted) return;
        if (values != null) {
          change(
            () => plan['calibration'] = {
              'a': points[0],
              'b': points[1],
              'metres': num.tryParse(
                values['Reale Länge [m]']!.replaceAll(',', '.'),
              ),
              'source': values['Quelle / Bezug'],
              'perspectiveConfirmed':
                  values['Perspektive geprüft (ja/nein)'] == 'ja',
            },
          );
        }
        setState(() {
          measuring = false;
          points.clear();
        });
      }
    } else if (routing) {
      setState(() => points.add(p));
    }
  }

  Future<void> circuit() async {
    final values = await fields('Stromkreis', {
      'Bezeichnung': '',
      'Verteilung': '',
      'Geräte-BMK (Komma getrennt)': '',
    });
    if (values == null || !mounted) return;
    final bmks = values['Geräte-BMK (Komma getrennt)']!
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    final devices = objects(
      d,
      'devices',
    ).where((v) => bmks.contains(v['bmk'])).toList();
    if (devices.length != bmks.length) {
      setState(() => error = 'Mindestens eine BMK wurde nicht gefunden.');
      return;
    }
    change(
      () => (plan.putIfAbsent('circuits', () => []) as List).add({
        'id': newId(),
        'name': values['Bezeichnung'],
        'distribution': values['Verteilung'],
        'deviceIds': devices.map((v) => v['id']).toList(),
      }),
    );
  }

  Future<String?> choose(String title, List<(String, String)> items) =>
      showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(title),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Keine passenden Einträge vorhanden.'),
              ),
            for (final i in items)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, i.$1),
                child: Text(i.$2),
              ),
          ],
        ),
      );
  Future<void> finishRoute() async {
    final instances = objects(
      d,
      'instances',
    ).where((v) => v['sheetId'] == widget.sheetId).toList();
    final choices = [
      for (final i in instances)
        (
          i['id'] as String,
          '${objectById(d, 'devices', i['deviceId'])['bmk']} · ${i['x']}/${i['y']}',
        ),
    ];
    final from = await choose('Startgerät', choices);
    if (from == null || !mounted) return;
    final to = await choose(
      'Zielgerät',
      choices.where((i) => i.$1 != from).toList(),
    );
    if (to == null || !mounted) return;
    final cid = await choose('Stromkreis', [
      for (final c in plan['circuits'] ?? [])
        (c['id'] as String, '${c['distribution']} / ${c['name']}'),
    ]);
    if (cid == null || !mounted) return;
    final values = await fields('Leitungsweg', {
      'Bezeichnung': 'Leitungsweg',
      'Höhen / Reserve [m]': '0',
    });
    if (values == null || !mounted) return;
    change(() {
      (plan.putIfAbsent('routes', () => []) as List).add({
        'id': newId(),
        'name': values['Bezeichnung'],
        'from': from,
        'to': to,
        'circuitId': cid,
        'points': [...points],
        'allowanceM': num.tryParse(
          values['Höhen / Reserve [m]']!.replaceAll(',', '.'),
        ),
      });
      routing = false;
      points.clear();
    });
  }

  void apply() {
    try {
      Navigator.pop(context, validateDrawing(d));
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Planart und Maßstab'),
      actions: [
        TextButton(
          onPressed: enabled ? apply : null,
          child: const Text('Planung übernehmen'),
        ),
      ],
    ),
    body: Column(
      children: [
        if (!enabled)
          const Text(
            'Darstellung zu klein für Bearbeitung oder nur Lesezugriff.',
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Expanded(
          child: Row(
            children: [
              if (MediaQuery.sizeOf(context).width >= 1000)
                SizedBox(
                  width: 320,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: plan['kind'],
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Planart'),
                        items: [
                          for (final e in planKinds.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: enabled
                            ? (v) => change(() {
                                plan['kind'] = v;
                                if (v == 'layout') plan['mmPerUnit'] ??= 1;
                              })
                            : null,
                      ),
                      if (plan['kind'] == 'layout')
                        TextButton(
                          onPressed: enabled
                              ? () async {
                                  final v = await fields('Aufbaumaßstab', {
                                    'Millimeter je Zeichnungseinheit':
                                        '${plan['mmPerUnit']}',
                                  });
                                  if (v != null && mounted) {
                                    change(
                                      () => plan['mmPerUnit'] = num.tryParse(
                                        v.values.single.replaceAll(',', '.'),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          child: Text(
                            '${plan['mmPerUnit']} mm je Einheit ändern',
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: enabled ? background : null,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Bildvorlage laden'),
                      ),
                      if (plan['background'] != null) ...[
                        Text(
                          '${plan['background']['origin']} · Revision ${plan['background']['revision']}',
                        ),
                        SwitchListTile(
                          title: const Text('Bildvorlage sperren'),
                          value: plan['background']['locked'],
                          onChanged: enabled
                              ? (v) => change(
                                  () => plan['background']['locked'] = v,
                                )
                              : null,
                        ),
                        TextButton(
                          onPressed:
                              enabled && plan['background']['locked'] == false
                              ? alignBackground
                              : null,
                          child: const Text('Vorlage ausrichten'),
                        ),
                        TextButton(
                          onPressed: enabled
                              ? () => change(() {
                                  plan.remove('background');
                                  plan.remove('calibration');
                                })
                              : null,
                          child: const Text('Vorlage entfernen'),
                        ),
                      ],
                      const Divider(),
                      OutlinedButton(
                        onPressed: enabled
                            ? () => change(() {
                                measuring = true;
                                routing = false;
                                points.clear();
                              })
                            : null,
                        child: Text(
                          measuring
                              ? 'Messpunkt ${points.length + 1} auf dem Blatt wählen'
                              : 'Maßstab: zwei Punkte wählen',
                        ),
                      ),
                      const Text(
                        'Zwei Punkte korrigieren keine Perspektive. Schrägfotos vorab entzerren; Länge erst nach bestätigter Prüfung.',
                      ),
                      if (plan['calibration'] != null)
                        Text(
                          '${plan['calibration']['metres']} m · ${plan['calibration']['source']} · Perspektive ${plan['calibration']['perspectiveConfirmed'] == true ? 'geprüft' : 'offen'}',
                        ),
                      const Divider(),
                      OutlinedButton(
                        onPressed: enabled ? circuit : null,
                        child: const Text('Stromkreis anlegen'),
                      ),
                      for (final c
                          in (plan['circuits'] as List? ?? []).cast<Json>())
                        ListTile(
                          title: Text('${c['distribution']} / ${c['name']}'),
                          subtitle: Text('${c['deviceIds'].length} Geräte'),
                          trailing: IconButton(
                            tooltip: 'Stromkreis entfernen',
                            onPressed: enabled
                                ? () => change(() {
                                    (plan['routes'] as List?)?.removeWhere(
                                      (r) => r['circuitId'] == c['id'],
                                    );
                                    (plan['circuits'] as List).remove(c);
                                  })
                                : null,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      OutlinedButton(
                        onPressed: enabled
                            ? () => change(() {
                                routing = true;
                                measuring = false;
                                points.clear();
                              })
                            : null,
                        child: const Text('Leitungsweg zeichnen'),
                      ),
                      if (routing) ...[
                        Text(
                          '${points.length} Stützpunkte; Start/Ziel beim Abschließen wählen.',
                        ),
                        FilledButton(
                          onPressed: finishRoute,
                          child: const Text('Leitungsweg abschließen'),
                        ),
                      ],
                      for (final r
                          in (plan['routes'] as List? ?? []).cast<Json>())
                        ListTile(
                          title: Text(r['name']),
                          subtitle: Text(
                            '${routeLength(d, plan, r)['metres'] ?? 'Maßstab fehlt'} m inkl. Zuschlag',
                          ),
                          trailing: IconButton(
                            tooltip: 'Weg entfernen',
                            onPressed: enabled
                                ? () => change(
                                    () => (plan['routes'] as List).remove(r),
                                  )
                                : null,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      if (measuring || routing)
                        TextButton(
                          onPressed: () => change(() {
                            measuring = false;
                            routing = false;
                            points.clear();
                          }),
                          child: const Text('Werkzeug abbrechen'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: DrawingCanvas(
                  drawing: d,
                  sheetId: widget.sheetId,
                  projectName: 'Planung',
                  version: 0,
                  selected: selected,
                  editable: enabled,
                  onTap: tap,
                  onSelect: (id) => setState(() => selected = id),
                  onMove: (id, p) => change(() {
                    final i = objectById(d, 'instances', id);
                    i['x'] = (p.dx / 20).round().clamp(4, 56) * 20;
                    i['y'] = (p.dy / 20).round().clamp(5, 33) * 20;
                  }),
                  onPort: (ref) {
                    final p = endpointPosition(d, ref);
                    tap(Offset(p.x, p.y));
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
