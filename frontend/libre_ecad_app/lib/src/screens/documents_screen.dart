import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ecad_core/ecad_core.dart';

import '../api/workspace_api.dart';
import '../models.dart';
import '../export/pdf_download.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.session,
    required this.projectId,
    required this.version,
    this.hasDraft = false,
    this.api,
  });
  final WorkspaceApi? api;
  final Session session;
  final String projectId;
  final int version;
  final bool hasDraft;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final api = widget.api ?? WorkspaceApi(widget.session);
  late String source = 'version=${widget.version}';
  Json? result;
  List<Json> versions = [], releases = [];
  String? error;
  bool busy = false;
  String get path => 'projects/${widget.projectId}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final responses = await Future.wait([
        api.request('GET', '$path/drawing/history'),
        api.request('GET', '$path/releases'),
        api.request('GET', '$path/documents?$source'),
      ]);
      if (!mounted) return;
      setState(() {
        versions = (responses[0]['versions'] as List).cast<Json>();
        releases = (responses[1]['releases'] as List).cast<Json>();
        result = responses[2];
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> approve() async {
    final findings = (result!['findings'] as List).cast<Json>();
    final reason = TextEditingController();
    final exceptions = {
      for (final f in findings) f['id'] as String: TextEditingController(),
    };
    final form = GlobalKey<FormState>();
    bool confirmed = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            'Arbeitsstand V${result!['project']['version']} festschreiben',
          ),
          content: SizedBox(
            width: 660,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Die ausgewählte Zeichnung, Metadaten, Listen und PDF werden gemeinsam unveränderlich archiviert. Spätere Änderungen bleiben Arbeitsstände.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: reason,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Freigabebegründung',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Begründung fehlt.' : null,
                    ),
                    for (final f in findings) ...[
                      const SizedBox(height: 12),
                      Text(f['message']),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: exceptions[f['id']],
                        maxLength: 1000,
                        decoration: InputDecoration(
                          labelText: 'Ausnahme begründen: ${f['id']}',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Hinweis prüfen und Ausnahme begründen.'
                            : null,
                      ),
                    ],
                    CheckboxListTile(
                      value: confirmed,
                      onChanged: (v) => update(() => confirmed = v ?? false),
                      title: const Text(
                        'Ich habe diesen Stand und alle Hinweise fachlich geprüft.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: confirmed
                  ? () {
                      if (form.currentState!.validate()) Navigator.pop(c, true);
                    }
                  : null,
              child: const Text('Verbindlich festschreiben'),
            ),
          ],
        ),
      ),
    );
    final reasonText = reason.text.trim(),
        exceptionTexts = {
          for (final e in exceptions.entries) e.key: e.value.text.trim(),
        };
    // Closing route animation can still reference form fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    reason.dispose();
    for (final c in exceptions.values) {
      c.dispose();
    }
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await api.request('POST', '$path/releases', {
        'version': result!['project']['version'],
        'reason': reasonText,
        'exceptions': exceptionTexts,
        'confirmed': true,
      });
      source = 'release=${response['release']['id']}';
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget table(String title, List<dynamic> rows, Map<String, String> fields) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Text('Keine Einträge.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final label in fields.values)
                        DataColumn(label: Text(label)),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            for (final key in fields.keys)
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: SelectableText('${row[key] ?? ''}'),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final r = result,
        data = r?['data'] as Json?,
        findings = (r?['findings'] as List? ?? []).cast<Json>();
    final released = r?['source'] == 'release';
    return Scaffold(
      appBar: AppBar(title: const Text('Dokumente und Freigabe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Eine Quelle für Zeichnungen, Listen und PDF.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (widget.hasDraft)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Ein ungespeicherter Entwurf bleibt im Editor. Die Ausgabe verwendet ausschließlich den hier gewählten gespeicherten Stand.',
              ),
            ),
          if (versions.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(source),
              initialValue: source,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ausgabequelle ausdrücklich wählen',
              ),
              items: [
                for (final p in versions.reversed)
                  DropdownMenuItem(
                    value: 'version=${p['version']}',
                    child: Text(
                      '${api.isOffline ? 'Offline-Entwurf auf Basis' : 'Arbeitsstand'} V${p['version']} · nicht freigegeben',
                    ),
                  ),
                for (final p in releases.reversed)
                  DropdownMenuItem(
                    value: 'release=${p['id']}',
                    child: Text(
                      'Festgeschrieben V${p['version']} · ${p['username']} · ${p['at']}',
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      if (v != null) {
                        source = v;
                        load();
                      }
                    },
            ),
          const SizedBox(height: 16),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : load,
                      child: const Text('Ausgewählten Stand neu laden'),
                    ),
                  ],
                ),
              ),
            ),
          if (r != null && data != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                Chip(
                  label: Text(
                    '${released ? 'Festgeschrieben' : 'Nicht freigegeben'} · Projektversion ${data['version']}',
                  ),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            await downloadPdf(
                              base64Decode(r['pdf']),
                              'libre-ecad-v${data['version']}-${released ? 'festgeschrieben' : 'arbeitsstand'}.pdf',
                            );
                          } catch (e) {
                            if (mounted) setState(() => error = '$e');
                          }
                        },
                  icon: const Icon(Icons.download),
                  label: const Text('PDF herunterladen'),
                ),
                if (!api.isOffline &&
                    !released &&
                    widget.session.role == UserRole.admin)
                  OutlinedButton.icon(
                    onPressed:
                        busy || findings.any((f) => f['severity'] == 'error')
                        ? null
                        : approve,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Stand fachlich festschreiben'),
                  ),
              ],
            ),
            if (released)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  'Git-Commit: ${r['release']['commit']}\nPDF SHA-256: ${r['release']['sha256']}\nFreigabe: ${r['approval']['reason']}',
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Plausibilitätsprüfung · ${findings.length} Hinweise',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Prüft Verweise und Anschlussbelegung der synthetischen Bibliothek. Keine Normprüfung.',
            ),
            if (findings.isEmpty)
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Keine Hinweise aus diesen Prüfregeln.'),
              ),
            for (final f in findings)
              ListTile(
                leading: Icon(
                  f['severity'] == 'error'
                      ? Icons.error_outline
                      : Icons.warning_amber,
                ),
                title: Text(f['message']),
                subtitle: Text(
                  released
                      ? 'Ausnahme: ${r['approval']['exceptions'][f['id']] ?? '—'}'
                      : '${f['id']}',
                ),
                trailing: !released && f['sheetId'] != ''
                    ? const Icon(Icons.open_in_new)
                    : null,
                onTap: !released && f['sheetId'] != ''
                    ? () => Navigator.pop(context, {
                        'finding': f,
                        'version': data['version'],
                      })
                    : null,
              ),
            table('Inhaltsverzeichnis', data['sheets'], {
              'number': 'Blatt',
              'title': 'Titel',
            }),
            table('Klemmenliste', data['terminals'], {
              'bmk': 'BMK',
              'terminal': 'Anschluss',
              'connections': 'Verbindungen',
            }),
            table('Verbindungsliste', data['connections'], {
              'sheet': 'Blatt',
              'from': 'Von',
              'to': 'Nach',
              'cable': 'Kabel',
              'core': 'Ader',
            }),
            table('Kabel- und Aderliste', data['cables'], {
              'bmk': 'Kabel',
              'core': 'Ader',
              'color': 'Farbe',
              'connections': 'Verbindungen',
            }),
            table('Materialliste', data['material'], {
              'bmk': 'BMK',
              'label': 'Bezeichnung',
              'type': 'Typ',
              'quantity': 'Anzahl',
              'positions': 'Positionen',
            }),
          ],
        ],
      ),
    );
  }
}
