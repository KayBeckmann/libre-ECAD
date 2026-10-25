import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

import '../api/workspace_api.dart';
import '../models.dart';
import '../drawing/drawing_canvas.dart';

class MacrosScreen extends StatefulWidget {
  const MacrosScreen({
    super.key,
    required this.api,
    required this.drawing,
    required this.editable,
    this.selectionDrawing,
  });
  final WorkspaceApi api;
  final Json drawing;
  final Json? selectionDrawing;
  final bool editable;
  @override
  State<MacrosScreen> createState() => _MacrosScreenState();
}

class _MacrosScreenState extends State<MacrosScreen> {
  String scope = 'personal', query = '';
  String? error;
  List<Json> rows = [];
  bool busy = false;
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
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final r = scope == 'global'
          ? await widget.api.request('POST', 'contributions', {
              'action': 'publicMacros',
            })
          : await widget.api.request('GET', 'macros/?scope=$scope');
      if (mounted) setState(() => rows = (r['macros'] as List).cast<Json>());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String body) => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Bestätigen'),
        ),
      ],
    ),
  ).then((v) => v == true);
  Future<void> edit([Json? old, bool selection = false]) async {
    final name = TextEditingController(text: old?['name'] ?? ''),
        origin = TextEditingController(text: old?['origin'] ?? ''),
        license = TextEditingController(text: old?['license'] ?? ''),
        groups = TextEditingController(
          text: (old?['groups'] as List? ?? []).join(', '),
        );
    bool replace = old == null;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(
            old == null
                ? selection
                      ? 'Auswahl als Makro speichern'
                      : 'Projektblätter als Makro speichern'
                : 'Makroversion bearbeiten',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final pair in [
                    (name, 'Name'),
                    (origin, 'Herkunft'),
                    (license, 'Lizenz'),
                    (groups, 'Gruppen (Komma getrennt)'),
                  ])
                    TextField(
                      controller: pair.$1,
                      decoration: InputDecoration(labelText: pair.$2),
                    ),
                  if (old != null)
                    CheckboxListTile(
                      value: replace,
                      onChanged: (v) => set(() => replace = v!),
                      title: const Text(
                        'Geometrie durch alle aktuellen Projektblätter ersetzen',
                      ),
                    ),
                  Text(
                    selection
                        ? 'Nur Bauteile mit Mittelpunkt im Rahmen, enthaltene Knoten und vollständig interne Leitungen. Keine Hintergrundbilder, Blattfortsetzungen, externen Leitungen oder Berechnungen. Vor dem Einfügen Vorschau prüfen.'
                        : 'Die Vorlage enthält Geräte, Verbindungen und eingebettete Daten aller übernommenen Blätter. Bestehende Einfügungen bleiben unverändert.',
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
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Makro speichern'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted && enabled) {
      try {
        final body = {
          'name': name.text,
          'origin': origin.text,
          'license': license.text,
          'groups': groups.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          'drawing': replace
              ? selection
                    ? widget.selectionDrawing!
                    : widget.drawing
              : old!['drawing'],
          if (old != null) 'version': old['version'],
          if (old == null) 'scope': scope,
        };
        await widget.api.request(
          old == null ? 'POST' : 'PATCH',
          old == null ? 'macros/' : 'macros/${old['id']}',
          body,
        );
        await load();
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in [name, origin, license, groups]) {
      c.dispose();
    }
  }

  Future<void> preview(Json a, {bool insert = false}) async {
    var sheet = objects(a['drawing'], 'sheets').first['id'] as String;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Dialog(
          child: SizedBox(
            width: 1100,
            height: 760,
            child: Column(
              children: [
                ListTile(
                  title: Text('${a['name']} · V${a['version']}'),
                  subtitle: Text('${a['origin']} · ${a['license']}'),
                ),
                DropdownButton<String>(
                  value: sheet,
                  items: [
                    for (final s in objects(a['drawing'], 'sheets'))
                      DropdownMenuItem(
                        value: s['id'],
                        child: Text('${s['number']} · ${s['title']}'),
                      ),
                  ],
                  onChanged: (v) => set(() => sheet = v!),
                ),
                Expanded(
                  child: DrawingCanvas(
                    drawing: a['drawing'],
                    sheetId: sheet,
                    projectName: a['name'],
                    version: a['version'],
                    selected: null,
                    editable: false,
                    onTap: (_) {},
                    onSelect: (_) {},
                    onMove: (_, _) {},
                    onPort: (_) {},
                  ),
                ),
                Text(
                  insert
                      ? 'Neue Blätter und Geräte mit neuen IDs/BMK. ${objects(a['drawing'], 'devices').length} Geräte, ${objects(a['drawing'], 'sheets').length} Blätter.'
                      : 'Unabhängige, gespeicherte Vorlagenversion.',
                ),
                OverflowBar(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Schließen'),
                    ),
                    if (insert && enabled)
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Als neue Blätter einfügen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (yes == true && mounted && enabled) {
      try {
        Navigator.pop(
          context,
          insertMacro(widget.drawing, a['drawing'], provenance: a),
        );
      } catch (e) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> history(Json a) async {
    try {
      final r = await widget.api.request('GET', 'macros/${a['id']}/history');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Makroversionen'),
          children: [
            for (final v in (r['versions'] as List).reversed)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(c);
                  preview(v, insert: true);
                },
                child: Text('Version ${v['version']} · ${v['updatedAt']}'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> copy(Json a, String target) async {
    try {
      if (!await confirm(
        'Makro kopieren?',
        'Eigenständige Kopie in ${target == 'company' ? 'den Firmenstamm' : 'den persönlichen Stamm'}. Quelle V${a['version']} bleibt unverändert.',
      )) {
        return;
      }
      await widget.api.request(
        'POST',
        'macros/${scope == 'global' ? 'global/' : ''}${a['id']}/copy',
        {'scope': target, 'version': a['version']},
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> publish(Json a) async {
    await preview(a);
    if (!mounted || !enabled) return;
    if (!await confirm(
      'Makro zur öffentlichen Prüfung einreichen?',
      'Alle enthaltenen Zeichnungsdaten, Artikelbezüge, Beschriftungen und Bildvorlagen werden an den globalen Katalog übertragen. Ich habe die Vorschau geprüft und besitze die Rechte zur Weitergabe unter ${a['license']}. Erst eine Moderation veröffentlicht den Beitrag.',
    )) {
      return;
    }
    try {
      final created = await widget.api.request('POST', 'contributions', {
        'action': 'create',
        'source': 'userUpload',
        'rightsConfirmed': true,
        'payload': {
          'kind': 'macro',
          'articleNumber': 'MACRO-${a['id']}',
          'name': a['name'],
          'origin': a['origin'],
          'license': a['license'],
          'attribution': a['origin'],
          'groups': a['groups'],
          'drawing': a['drawing'],
        },
      });
      await widget.api.request('POST', 'contributions', {
        'action': 'submit',
        'confirmed': true,
        'reason': 'Makrovorschau und Weitergaberechte geprüft.',
        'id': created['id'],
        'version': created['version'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Makro eingereicht. Freigabestatus unter Katalogbeiträge.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Makrobibliothek'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          tooltip: 'Aktualisieren',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'personal', label: Text('Persönlich')),
                  ButtonSegment(value: 'company', label: Text('Firma')),
                  ButtonSegment(
                    value: 'global',
                    label: Text('Global freigegeben'),
                  ),
                ],
                selected: {scope},
                onSelectionChanged: (v) {
                  setState(() => scope = v.single);
                  load();
                },
              ),
              if (widget.selectionDrawing != null && scope != 'global')
                FilledButton.icon(
                  onPressed:
                      enabled &&
                          !busy &&
                          (scope == 'personal' ||
                              widget.api.session.role == UserRole.admin)
                      ? () => edit(null, true)
                      : null,
                  icon: const Icon(Icons.select_all),
                  label: Text(
                    'Auswahl als Makro speichern (${objects(widget.selectionDrawing!, 'instances').length} Bauteile)',
                  ),
                ),
              if (scope != 'global')
                FilledButton.icon(
                  onPressed:
                      enabled &&
                          !busy &&
                          (scope == 'personal' ||
                              widget.api.session.role == UserRole.admin)
                      ? () => edit()
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Projekt als Makro speichern'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Name oder Gruppe suchen',
            ),
            onChanged: (v) => setState(() => query = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (rows.isEmpty)
                      const ListTile(
                        title: Text('Keine Makros in diesem Bereich.'),
                      ),
                    for (final a in rows.where(
                      (a) => '${a['name']} ${a['groups']}'
                          .toLowerCase()
                          .contains(query),
                    ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a['name']} · V${a['version']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${(a['groups'] as List).join(' / ')} · ${a['license']}',
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => preview(a),
                                    child: const Text('Vorschau'),
                                  ),
                                  FilledButton(
                                    onPressed: enabled
                                        ? () => preview(a, insert: true)
                                        : null,
                                    child: const Text('Einfügen'),
                                  ),
                                  if (scope == 'global')
                                    TextButton(
                                      onPressed: enabled
                                          ? () => copy(a, 'personal')
                                          : null,
                                      child: const Text('Persönliche Kopie'),
                                    ),
                                  if (scope != 'global') ...[
                                    TextButton(
                                      onPressed: () => history(a),
                                      child: const Text('Versionen'),
                                    ),
                                    if (scope == 'personal' ||
                                        widget.api.session.role ==
                                            UserRole.admin)
                                      TextButton(
                                        onPressed: enabled
                                            ? () => edit(a)
                                            : null,
                                        child: const Text('Bearbeiten'),
                                      ),
                                    TextButton(
                                      onPressed: enabled
                                          ? () => copy(a, 'personal')
                                          : null,
                                      child: const Text('Persönliche Kopie'),
                                    ),
                                    if (widget.api.session.role ==
                                        UserRole.admin)
                                      TextButton(
                                        onPressed: enabled
                                            ? () => copy(a, 'company')
                                            : null,
                                        child: const Text('Firmenkopie'),
                                      ),
                                    TextButton(
                                      onPressed: enabled
                                          ? () => publish(a)
                                          : null,
                                      child: const Text(
                                        'Öffentlich einreichen',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
