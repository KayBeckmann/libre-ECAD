import 'dart:async';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

import 'documents_screen.dart';

import '../api/company_users_api.dart';
import '../api/workspace_api.dart';
import '../drawing/drawing_canvas.dart';
import '../drawing/drawing_controller.dart';
import '../models.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    super.key,
    required this.session,
    required this.projectId,
    this.api,
  });
  final Session session;
  final String projectId;
  final WorkspaceApi? api;
  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  late final api = widget.api ?? WorkspaceApi(widget.session);
  DrawingController? controller;
  Timer? heartbeat;
  String? error, sheetId, selected, pendingDevice;
  String name = '', tool = 'select', query = '';
  Json? pendingPort;
  int version = 0;
  bool busy = false, online = false, checking = false, canLeave = false;
  String get path =>
      'projects/${Uri.encodeComponent(widget.projectId)}/drawing';
  Json get d => controller!.drawing;
  @override
  void initState() {
    super.initState();
    load();
    heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => check());
  }

  @override
  void dispose() {
    heartbeat?.cancel();
    controller?.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> check() async {
    if (checking || busy || controller == null) return;
    checking = true;
    try {
      await api.request('GET', path);
      if (mounted) {
        setState(() {
          if (!online) error = null;
          online = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          online = false;
          error = api.isOffline ? '$e' : 'Backend nicht erreichbar oder Zugriff entzogen. Entwurf bleibt im Fenster erhalten. Verbindung prüfen oder erneut anmelden.';
        });
      }
    } finally {
      checking = false;
    }
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final r = await api.request('GET', path);
      if (!mounted) return;
      controller?.dispose();
      controller = DrawingController(r['drawing'] as Json? ?? emptyDrawing())
        ..addListener(refresh);
      if (r['drawing'] != null) controller!.markSaved();
      setState(() {
        version = r['version'];
        name = r['projectName'];
        sheetId = objects(d, 'sheets').first['id'];
        online = true;
        error = null;
        selected = null;
        pendingPort = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          online = false;
          error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(
    String title,
    String message, {
    String action = 'Bestätigen',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  void change(void Function(Json) edit) {
    if (busy || !online) return;
    try {
      controller!.change(edit);
      setState(() => error = null);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  bool get hasEditingSpace =>
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.sizeOf(context).height -
              kToolbarHeight -
              MediaQuery.paddingOf(context).vertical >=
          500;

  Future<void> save() async {
    if (!online || busy || !hasEditingSpace) return;
    setState(() => busy = true);
    try {
      final r = await api.request('PUT', path, {
        'version': version,
        'drawing': d,
      });
      if (mounted) {
        controller!.markSaved();
        setState(() {
          version = r['version'];
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => error = '$e');
        if (e.statusCode == 409) {
          await resolveConflict();
        } else if (e.statusCode == 401 || e.statusCode == 404) {
          setState(() => online = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          online = false;
          error = 'Speichern fehlgeschlagen. Entwurf bleibt im Fenster erhalten. Verbindung prüfen und erneut speichern.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> documents() async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsScreen(
          session: widget.session,
          projectId: widget.projectId,
          version: version,
          hasDraft: controller!.dirty,
          api: api,
        ),
      ),
    );
    if (!mounted) return;
    if (result?['finding'] != null) {
      final finding = result!['finding'] as Json;
      if (result['version'] != version) {
        setState(
          () => error = 'Der Hinweis gehört zu einem anderen Arbeitsstand. Diesen zunächst über die Historie laden.',
        );
      } else if (objects(
        d,
        'sheets',
      ).any((s) => s['id'] == finding['sheetId'])) {
        setState(() {
          sheetId = finding['sheetId'];
          selected = finding['objectId'];
        });
      }
    }
    await check();
  }

  Future<void> resolveConflict() async {
    try {
      final remote = await api.request('GET', path);
      if (!mounted) return;
      setState(() => busy = false);
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Konflikt: Arbeitsstände vergleichen'),
          content: SizedBox(
            width: 1000,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lokal auf Stand $version · Serverstand ${remote['version']}. Es wird nichts automatisch zusammengeführt. Eine Übernahme ersetzt die gesamte Zeichnung; Projektmitglieder bleiben serverseitig erhalten.',
                ),
                const SizedBox(height: 16),
                Text(
                  '${drawingChanges(d, remote['drawing'] as Json? ?? emptyDrawing()).length} abweichende Objekte · Details je Seite unten',
                ),
                SizedBox(
                  height: 110,
                  child: ListView(
                    children: [
                      for (final change in drawingChanges(
                        d,
                        remote['drawing'] as Json? ?? emptyDrawing(),
                      ))
                        Text(
                          '${change['kind']} · ${change['id']} · ${change['change']}\nLokal: ${change['before']?['bmk'] ?? change['before']?['title'] ?? change['before']?['label'] ?? '—'} / Server: ${change['after']?['bmk'] ?? change['after']?['title'] ?? change['after']?['label'] ?? '—'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            'LOKAL\n${canonicalJson(d)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            'SERVER\n${canonicalJson(remote['drawing'] as Json? ?? {})}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Entwurf behalten / abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'server'),
              child: const Text('Serverzeichnung übernehmen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'local'),
              child: const Text('Lokale Zeichnung bewusst speichern'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'server') {
        controller!.replace(remote['drawing'] as Json? ?? emptyDrawing());
        controller!.markSaved();
        setState(() {
          version = remote['version'];
          name = remote['projectName'];
          sheetId = objects(d, 'sheets').first['id'];
          selected = null;
          pendingPort = null;
          error = null;
        });
      } else {
        // The user explicitly selected a side. Another concurrent change still conflicts.
        final result = await api.request('PUT', path, {
          'version': remote['version'],
          'drawing': d,
        });
        if (mounted) {
          controller!.markSaved();
          setState(() {
            version = result['version'];
            error = null;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Konflikt bleibt offen. $e');
    }
  }

  Future<void> history() async {
    setState(() => busy = true);
    try {
      final r = await api.request('GET', '$path/history');
      if (!mounted) return;
      setState(() => busy = false);
      final picked = await showDialog<Json>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Gespeicherte Arbeitsstände'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: ListView(
              children: [
                const Text(
                  'Eine Wiederherstellung wird als Entwurf geladen. Erst „Speichern“ erzeugt eine neue Version; die Historie bleibt erhalten.',
                ),
                for (final v in (r['versions'] as List).reversed)
                  ListTile(
                    title: Text('Arbeitsstand ${v['version']}'),
                    subtitle: Text(
                      '${v['updatedAt']} · ${objects(v['drawing'], 'devices').length} Geräte',
                    ),
                    trailing: const Icon(Icons.restore),
                    onTap: () => Navigator.pop(c, v['drawing'] as Json),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      if (picked != null &&
          mounted &&
          await confirm(
            'Arbeitsstand wiederherstellen?',
            'Der gewählte Inhalt ersetzt den lokalen Entwurf. Rückgängig ist bis zum Schließen möglich.',
            action: 'Als Entwurf laden',
          )) {
        controller!.replace(picked);
        setState(() {
          sheetId = objects(d, 'sheets').first['id'];
          selected = null;
          pendingPort = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          width: 420,
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
    // Dispose after the route's closing transition has released its text fields.
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in controls.values) {
        c.dispose();
      }
    });
    return result;
  }

  Future<void> sheet({bool create = false}) async {
    final old = objectById(d, 'sheets', sheetId!);
    final nextNumber =
        objects(
          d,
          'sheets',
        ).map((o) => o['number'] as int).reduce((a, b) => a > b ? a : b) +
        1;
    final values = await fields(create ? 'Blatt anlegen' : 'Blatt bearbeiten', {
      'Blattnummer': create ? '$nextNumber' : '${old['number']}',
      'Titel': create ? 'Neues Blatt' : old['title'],
    });
    if (values == null || !mounted) return;
    final id = create ? newId() : sheetId!;
    change((d) {
      final value = {
        'id': id,
        'number': int.tryParse(values['Blattnummer']!),
        'title': values['Titel'],
      };
      if (create) {
        (d['sheets'] as List).add(value);
      } else {
        objectById(d, 'sheets', id).addAll(value);
      }
    });
    if (objects(d, 'sheets').any((s) => s['id'] == id)) {
      setState(() => sheetId = id);
    }
  }

  Future<void> sample(String kind) async {
    if (!await confirm(
          'Synthetische Arbeitsprobe laden?',
          'Die Arbeitsprobe ersetzt den lokalen Entwurf. Sie ist keine geprüfte Schaltung. Rückgängig bleibt möglich.',
          action: 'Arbeitsprobe laden',
        ) ||
        !mounted) {
      return;
    }
    change((d) {
      d.clear();
      d.addAll(sampleDrawing(kind));
    });
    setState(() {
      sheetId = objects(d, 'sheets').first['id'];
      selected = null;
      pendingPort = null;
      tool = 'select';
    });
  }

  void tap(Offset pos) {
    final x = (pos.dx / 20).round() * 20, y = (pos.dy / 20).round() * 20;
    if (x < 80 || x > 1120 || y < 100 || y > 660) return;
    if (tool.startsWith('place:')) {
      String? created;
      change((d) {
        created = addSymbol(
          d,
          tool.substring(6),
          sheetId!,
          x,
          y,
          deviceId: pendingDevice,
        )['id'];
      });
      setState(() {
        selected = created;
        pendingDevice = null;
        tool = 'select';
      });
    } else if (tool == 'node') {
      change(
        (d) => (d['nodes'] as List).add({
          'id': newId(),
          'sheetId': sheetId,
          'x': x,
          'y': y,
        }),
      );
    } else {
      setState(() => selected = null);
    }
  }

  void connect(Json ref) {
    if (tool != 'connect') {
      if (tool == 'select' && ref['kind'] == 'port') {
        setState(() {
          selected = ref['instanceId'];
          error = null;
        });
      } else {
        setState(
          () => error = 'Zum Verbinden zuerst das Werkzeug „Verbinden“ wählen.',
        );
      }
      return;
    }
    if (pendingPort == null) {
      setState(() => pendingPort = ref);
      return;
    }
    final before = canonicalJson(d);
    change(
      (d) => (d['wires'] as List).add({
        'id': newId(),
        'sheetId': sheetId,
        'from': pendingPort,
        'to': ref,
      }),
    );
    if (canonicalJson(d) != before) setState(() => pendingPort = null);
  }

  void move(String id, Offset p) {
    if (tool != 'select') return;
    change((d) {
      final i = objectById(d, 'instances', id);
      i['x'] = ((p.dx / 20).round() * 20).clamp(80, 1120);
      i['y'] = ((p.dy / 20).round() * 20).clamp(100, 660);
    });
  }

  Future<void> continuation() async {
    final others = objects(
      d,
      'sheets',
    ).where((s) => s['id'] != sheetId).toList();
    if (others.isEmpty) {
      setState(
        () => error = 'Für eine Fortsetzung zuerst ein zweites Blatt anlegen.',
      );
      return;
    }
    final values = await fields('Blattfortsetzung anlegen', {
      'Signalname': 'Signal',
      'Zielblattnummer': '${others.first['number']}',
    });
    if (values == null || !mounted) return;
    final targets = others.where(
      (s) => '${s['number']}' == values['Zielblattnummer'],
    );
    if (targets.isEmpty) {
      setState(() => error = 'Zielblatt nicht gefunden.');
      return;
    }
    final link = newId();
    change((d) {
      for (final sid in [sheetId, targets.first['id']]) {
        (d['continuations'] as List).add({
          'id': newId(),
          'sheetId': sid,
          'x': 1000,
          'y': 600,
          'linkId': link,
          'label': values['Signalname'],
        });
      }
    });
  }

  Future<void> deviceEdit(Json i) async {
    final device = objectById(d, 'devices', i['deviceId']);
    final values = await fields('Betriebsmittel bearbeiten', {
      'BMK': device['bmk'],
      'Bezeichnung': device['label'],
      for (final t in device['terminals'] as List)
        'Anschluss ${t['id']}': t['label'],
    });
    if (values == null || !mounted) return;
    change((d) {
      final device = objectById(d, 'devices', i['deviceId']);
      device['bmk'] = values['BMK'];
      device['label'] = values['Bezeichnung'];
      for (final t in device['terminals'] as List) {
        t['label'] = values['Anschluss ${t['id']}'];
      }
    });
  }

  Future<void> cable(Json wire) async {
    final values = await fields('Kabel / Ader zuordnen', {
      'Kabel-BMK': 'W${objects(d, 'cables').length + 1}',
      'Aderbezeichnung': '1',
      'Farbe': 'nicht festgelegt',
    });
    if (values == null || !mounted) return;
    change((d) {
      final matches = objects(
        d,
        'cables',
      ).where((c) => c['bmk'] == values['Kabel-BMK']);
      Json cable;
      if (matches.isEmpty) {
        cable = {'id': newId(), 'bmk': values['Kabel-BMK'], 'cores': <Json>[]};
        (d['cables'] as List).add(cable);
      } else {
        cable = matches.first;
      }
      final matchesCore = (cable['cores'] as List).where(
        (c) => c['label'] == values['Aderbezeichnung'],
      );
      Json core;
      if (matchesCore.isEmpty) {
        core = {
          'id': newId(),
          'label': values['Aderbezeichnung'],
          'color': values['Farbe'],
        };
        (cable['cores'] as List).add(core);
      } else {
        core = matchesCore.first as Json;
        core['color'] = values['Farbe'];
      }
      objectById(
        d,
        'wires',
        wire['id'],
      ).addAll({'cableId': cable['id'], 'coreId': core['id']});
    });
  }

  Future<void> splitWire(Json wire) async {
    if (wire['cableId'] != null) {
      setState(
        () => error = 'Kabelader zuerst lösen; eine Ader darf nur einer Leitung zugeordnet sein.',
      );
      return;
    }
    final values = await fields('Expliziten Abzweig einfügen', {
      'X [Raster 20]': '400',
      'Y [Raster 20]': '400',
    });
    if (values == null || !mounted) return;
    change((d) {
      final node = {
        'id': newId(),
        'sheetId': sheetId,
        'x': int.tryParse(values['X [Raster 20]']!),
        'y': int.tryParse(values['Y [Raster 20]']!),
      };
      (d['nodes'] as List).add(node);
      final w = objectById(d, 'wires', wire['id']);
      final end = w['to'];
      w['to'] = pointRef('node', node['id'] as String);
      (d['wires'] as List).add({
        'id': newId(),
        'sheetId': sheetId,
        'from': pointRef('node', node['id'] as String),
        'to': end,
      });
    });
  }

  Future<void> pointEdit(String kind, Json point) async {
    final values = await fields(
      kind == 'nodes' ? 'Knoten verschieben' : 'Fortsetzung bearbeiten',
      {
        'X [Raster 20]': '${point['x']}',
        'Y [Raster 20]': '${point['y']}',
        if (kind == 'continuations') 'Signalname': point['label'],
      },
    );
    if (values == null || !mounted) return;
    change((d) {
      final o = objectById(d, kind, point['id']);
      o['x'] = int.tryParse(values['X [Raster 20]']!);
      o['y'] = int.tryParse(values['Y [Raster 20]']!);
      if (kind == 'continuations') {
        for (final c in objects(
          d,
          kind,
        ).where((c) => c['linkId'] == o['linkId'])) {
          c['label'] = values['Signalname'];
        }
      }
    });
  }

  Future<void> pointRemove(String kind, Json point) async {
    if (!await confirm(
          'Endpunkt entfernen?',
          'Zugehörige Leitungen werden entfernt. Bei einer Fortsetzung werden beide Enden entfernt.',
        ) ||
        !mounted) {
      return;
    }
    change((d) {
      final ids = objects(d, kind)
          .where(
            (o) => kind == 'nodes'
                ? o['id'] == point['id']
                : o['linkId'] == point['linkId'],
          )
          .map((o) => o['id'])
          .toSet();
      (d['wires'] as List).removeWhere(
        (w) => ids.contains(w['from']['id']) || ids.contains(w['to']['id']),
      );
      (d[kind] as List).removeWhere((o) => ids.contains(o['id']));
    });
    setState(() => pendingPort = null);
  }

  @override
  Widget build(BuildContext context) {
    final ready = controller != null;
    return PopScope(
      canPop: canLeave || !ready || !controller!.dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await confirm(
              'Ungespeicherten Entwurf verwerfen?',
              'Der Entwurf ist nur in diesem Fenster. Gespeicherte Arbeitsstände bleiben erhalten.',
              action: 'Verwerfen',
            ) &&
            mounted) {
          setState(() => canLeave = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(ready ? '$name · Schaltplan' : 'Schaltplan laden'),
          actions: [
            if (ready)
              IconButton(
                tooltip: 'Dokumente und Freigabe',
                onPressed: online && !busy ? documents : null,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
            if (ready)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    'V$version${controller!.dirty ? ' · ungespeichert' : ''}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: api.isOffline
                  ? 'Offline-Berechtigung prüfen'
                  : 'Verbindung prüfen',
              onPressed: busy ? null : () => ready ? check() : load(),
              icon: Icon(
                online ? Icons.cloud_done_outlined : Icons.cloud_off,
                color: online ? accent : Colors.red,
              ),
            ),
            if (ready)
              TextButton.icon(
                onPressed: online && !busy ? history : null,
                icon: const Icon(Icons.history),
                label: const Text('Historie'),
              ),
            if (ready)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed:
                      online && !busy && hasEditingSpace && controller!.dirty
                      ? save
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Speichern'),
                ),
              ),
          ],
        ),
        body: !ready
            ? Center(
                child: busy
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error ?? 'Laden fehlgeschlagen.'),
                          TextButton(
                            onPressed: load,
                            child: const Text('Erneut laden'),
                          ),
                        ],
                      ),
              )
            : LayoutBuilder(
                builder: (context, c) {
                  final compact = c.maxWidth < 1000 || c.maxHeight < 500;
                  final enabled = online && !busy && !compact;
                  return Column(
                    children: [
                      if (busy) const LinearProgressIndicator(minHeight: 2),
                      if (error != null)
                        Container(
                          width: double.infinity,
                          color: Theme.of(context).colorScheme.errorContainer,
                          padding: const EdgeInsets.all(8),
                          child: Text(error!, maxLines: 3),
                        ),
                      if (compact)
                        const MaterialBanner(
                          content: Text('Darstellung zu klein für Bearbeitung'),
                          actions: [SizedBox.shrink()],
                        ),
                      SizedBox(
                        height: 52,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              for (final mode in [
                                ('select', 'Auswählen', Icons.near_me_outlined),
                                (
                                  'connect',
                                  'Verbinden',
                                  Icons.polyline_outlined,
                                ),
                                ('node', 'Knoten', Icons.adjust),
                                (
                                  'pan',
                                  'Ansicht bewegen',
                                  Icons.pan_tool_outlined,
                                ),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(mode.$2),
                                    avatar: Icon(mode.$3, size: 16),
                                    selected: tool == mode.$1,
                                    onSelected: enabled
                                        ? (_) => setState(() {
                                            tool = mode.$1;
                                            pendingPort = null;
                                            pendingDevice = null;
                                          })
                                        : null,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Rückgängig',
                                onPressed: enabled && controller!.canUndo
                                    ? () {
                                        controller!.undo();
                                        resetSelection();
                                      }
                                    : null,
                                icon: const Icon(Icons.undo),
                              ),
                              IconButton(
                                tooltip: 'Wiederholen',
                                onPressed: enabled && controller!.canRedo
                                    ? () {
                                        controller!.redo();
                                        resetSelection();
                                      }
                                    : null,
                                icon: const Icon(Icons.redo),
                              ),
                              const VerticalDivider(indent: 12, endIndent: 12),
                              TextButton.icon(
                                onPressed: enabled ? continuation : null,
                                icon: const Icon(Icons.compare_arrows),
                                label: const Text('Blattfortsetzung'),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Synthetische Arbeitsproben',
                                enabled: enabled,
                                onSelected: sample,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'distribution',
                                    child: Text('TEST · Verteilerabgang'),
                                  ),
                                  PopupMenuItem(
                                    value: 'motor',
                                    child: Text('TEST · Steuer- / Motorabgang'),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Arbeitsproben'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            if (!compact)
                              SizedBox(
                                width: 220,
                                child: libraryPanel(enabled),
                              ),
                            Expanded(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            value: sheetId,
                                            items: [
                                              for (final s in objects(
                                                d,
                                                'sheets',
                                              ))
                                                DropdownMenuItem(
                                                  value: s['id'] as String,
                                                  child: Text(
                                                    '${s['number']} · ${s['title']}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                            onChanged: (v) => setState(() {
                                              sheetId = v;
                                              selected = null;
                                              pendingPort = null;
                                            }),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Blatt bearbeiten',
                                          onPressed: enabled
                                              ? () => sheet()
                                              : null,
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Blatt anlegen',
                                          onPressed: enabled
                                              ? () => sheet(create: true)
                                              : null,
                                          icon: const Icon(
                                            Icons.note_add_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: DrawingCanvas(
                                      drawing: d,
                                      sheetId: sheetId!,
                                      projectName: name,
                                      version: version,
                                      selected: selected,
                                      editable: enabled && tool != 'pan',
                                      pending: pendingPort,
                                      onTap: tap,
                                      onSelect: (id) =>
                                          setState(() => selected = id),
                                      onMove: move,
                                      onPort: connect,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!compact)
                              SizedBox(width: 280, child: inspector(enabled)),
                          ],
                        ),
                      ),
                      Container(
                        height: 30,
                        color: ink,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            pendingPort != null
                                ? 'Zielanschluss wählen · Werkzeugwechsel bricht ab'
                                : tool.startsWith('place:')
                                ? '${symbolByKey(tool.substring(6)).name}: zum Platzieren auf das Blatt klicken'
                                : 'Raster 20 · ${objects(d, 'devices').length} Geräte · ${nets(d).where((n) => n['connected'] == true).length} verbundene Netze · Arbeitsentwurf / synthetische Symbole',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  void resetSelection() {
    setState(() {
      if (!objects(d, 'sheets').any((s) => s['id'] == sheetId)) {
        sheetId = objects(d, 'sheets').first['id'];
      }
      selected = null;
      pendingPort = null;
    });
  }

  Widget libraryPanel(bool enabled) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'BAUTEILBIBLIOTHEK',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Bauteil suchen',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => query = v.toLowerCase()),
        ),
        const SizedBox(height: 12),
        for (final group in ['Verteilerabgang', 'Steuer- / Motorabgang'])
          ExpansionTile(
            key: ValueKey(group),
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            title: Text(
              group,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              for (final s in symbolLibrary.where(
                (s) => s.group == group && s.name.toLowerCase().contains(query),
              ))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 6),
                  leading: const Icon(Icons.memory_outlined, size: 20),
                  title: Text(s.name),
                  enabled: enabled,
                  selected: tool == 'place:${s.key}',
                  onTap: () => setState(() {
                    tool = 'place:${s.key}';
                    pendingDevice = null;
                    pendingPort = null;
                  }),
                ),
            ],
          ),
        const SizedBox(height: 16),
        const Text(
          'Eigene synthetische Glyphen\nMIT · keine Normsymbolbibliothek',
          style: TextStyle(fontSize: 11, color: Color(0xffa8bec1)),
        ),
      ],
    ),
  );
  String endpointLabel(Json ref) {
    if (ref['kind'] == 'port') {
      final i = objectById(d, 'instances', ref['instanceId']);
      return '${objectById(d, 'devices', i['deviceId'])['bmk']}:${ref['terminalId']}';
    }
    if (ref['kind'] == 'continuation') {
      return objectById(d, 'continuations', ref['id'])['label'];
    }
    return 'Knoten ${shortObjectId(ref['id'])}';
  }

  Widget inspector(bool enabled) {
    final views = objects(d, 'instances').where((i) => i['id'] == selected);
    final i = views.isEmpty ? null : views.first;
    final device = i == null ? null : objectById(d, 'devices', i['deviceId']);
    final sheetWires = objects(
      d,
      'wires',
    ).where((w) => w['sheetId'] == sheetId);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'EIGENSCHAFTEN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          if (i == null)
            const Text(
              'Symbol wählen oder aus der Bibliothek auf dem Blatt platzieren.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            Text(
              device!['bmk'],
              style: const TextStyle(
                fontSize: 24,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(device['label']),
            const SizedBox(height: 6),
            Text(
              'Position ${positionReference(d, i)} · ${i['x']}/${i['y']}',
              style: const TextStyle(fontSize: 12),
            ),
            TextButton.icon(
              onPressed: enabled ? () => deviceEdit(i) : null,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Kennung / Anschlüsse'),
            ),
            TextButton(
              onPressed: enabled
                  ? () async {
                      final proposal = proposedBmk(
                        d,
                        i['sheetId'],
                        symbolByKey(i['symbol']).code,
                        i['x'],
                        exceptDevice: device['id'],
                      );
                      if (await confirm(
                            'BMK-Vorschlag übernehmen?',
                            '${device['bmk']} -> $proposal. Alle Darstellungen erhalten dieselbe Kennung.',
                          ) &&
                          mounted) {
                        change(
                          (d) => objectById(d, 'devices', device['id'])['bmk'] =
                              proposal,
                        );
                      }
                    }
                  : null,
              child: const Text('BMK aus Position vorschlagen'),
            ),
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text(
                'Weitere Darstellung …',
                style: TextStyle(fontSize: 12),
              ),
              items: [
                for (final s in symbolLibrary.where(
                  (s) => s.deviceType == device['type'],
                ))
                  DropdownMenuItem(value: s.key, child: Text(s.name)),
              ],
              onChanged: enabled
                  ? (key) => setState(() {
                      tool = 'place:$key';
                      pendingDevice = device['id'];
                      pendingPort = null;
                    })
                  : null,
            ),
            for (final ref in crossReferences(d, device['id']))
              TextButton(
                onPressed: () => setState(() {
                  sheetId = ref['sheetId'];
                  selected = ref['instanceId'];
                  pendingPort = null;
                }),
                child: Text(
                  'Blatt ${ref['position']} · ${symbolByKey(ref['symbol']).name}',
                ),
              ),
            TextButton.icon(
              onPressed: enabled
                  ? () async {
                      if (await confirm(
                            'Darstellung entfernen?',
                            'Ihre Leitungen werden entfernt. Weitere Ansichten desselben Geräts bleiben erhalten.',
                          ) &&
                          mounted) {
                        controller!.removeInstance(i['id']);
                        resetSelection();
                      }
                    }
                  : null,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Darstellung entfernen'),
            ),
          ],
          const Divider(),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Verbindungen (${sheetWires.length})',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            initiallyExpanded: true,
            children: [
              for (final w in sheetWires)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${endpointLabel(w['from'])} -> ${endpointLabel(w['to'])}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  subtitle: w['cableId'] == null
                      ? null
                      : Text(
                          '${objectById(d, 'cables', w['cableId'])['bmk']} / Ader ${w['coreId']}',
                          style: const TextStyle(fontSize: 10),
                        ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Verbindung bearbeiten',
                    enabled: enabled,
                    onSelected: (action) async {
                      if (action == 'delete') {
                        if (await confirm(
                              'Verbindung trennen?',
                              'Nur diese Verbindung wird entfernt; Geräte bleiben erhalten.',
                            ) &&
                            mounted) {
                          change(
                            (d) => (d['wires'] as List).removeWhere(
                              (v) => v['id'] == w['id'],
                            ),
                          );
                        }
                      }
                      if (action == 'cable') await cable(w);
                      if (action == 'split') await splitWire(w);
                      if (action == 'uncable') {
                        change((d) {
                          final wire = objectById(d, 'wires', w['id']);
                          wire.remove('cableId');
                          wire.remove('coreId');
                        });
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Verbindung trennen'),
                      ),
                      PopupMenuItem(
                        value: 'split',
                        child: Text('Abzweig einfügen'),
                      ),
                      PopupMenuItem(
                        value: 'cable',
                        child: Text('Kabel / Ader zuordnen'),
                      ),
                      PopupMenuItem(
                        value: 'uncable',
                        child: Text('Kabelzuordnung lösen'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          for (final kind in ['nodes', 'continuations'])
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                kind == 'nodes' ? 'Knoten' : 'Blattfortsetzungen',
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                for (final o in objects(
                  d,
                  kind,
                ).where((o) => o['sheetId'] == sheetId))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      kind == 'nodes'
                          ? 'Knoten ${shortObjectId(o['id'])}'
                          : o['label'],
                      style: const TextStyle(fontSize: 11),
                    ),
                    subtitle: Text('${o['x']}/${o['y']}'),
                    onTap: enabled ? () => pointEdit(kind, o) : null,
                    trailing: IconButton(
                      tooltip: 'Endpunkt entfernen',
                      onPressed: enabled ? () => pointRemove(kind, o) : null,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
              ],
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Elektrische Netze',
              style: TextStyle(fontSize: 13),
            ),
            children: [
              for (final net in nets(d))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    net['connected']
                        ? Icons.hub_outlined
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  title: Text(
                    '${(net['wireIds'] as List).length} Leitungen · ${(net['endpoints'] as List).length} Endpunkte',
                    style: const TextStyle(fontSize: 11),
                  ),
                  subtitle: Text(
                    (net['endpoints'] as List)
                        .map((key) {
                          final s = (key as String).split(':');
                          if (s.first == 'port') {
                            return '${objectById(d, 'devices', s[1])['bmk']}:${s[2]}';
                          }
                          return '${s.first} ${shortObjectId(s[1])}';
                        })
                        .join(', '),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
