import 'package:flutter/material.dart';

import '../api/workspace_api.dart';
import '../models.dart';

const contributionStates = {
  'draft': 'Entwurf',
  'review': 'In Prüfung',
  'published': 'Veröffentlicht',
  'withdrawn': 'Zurückgezogen',
};

class ContributionsScreen extends StatefulWidget {
  const ContributionsScreen({super.key, required this.session});
  final Session session;
  @override
  State<ContributionsScreen> createState() => _ContributionsState();
}

class _ContributionsState extends State<ContributionsScreen> {
  late final api = WorkspaceApi(widget.session);
  List<dynamic> rows = [];
  Map<String, dynamic>? manufacturer;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await api.request('POST', 'contributions', {'action': 'list'});
      if (mounted) {
        setState(() {
          rows = d['results'] as List;
          manufacturer = d['manufacturer'] as Map<String, dynamic>?;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> run(Map<String, dynamic> body) async {
    setState(() => busy = true);
    try {
      final d = await api.request('POST', 'contributions', body);
      if (mounted && (d['duplicates'] as List? ?? []).isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Es gibt bereits Artikel mit dieser Nummer. Bitte vor Einreichung im Katalog prüfen.',
            ),
          ),
        );
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transition(Map<String, dynamic> d, String action) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          action == 'submit'
              ? 'Öffentlich einreichen?'
              : 'Beitrag zurückziehen?',
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action == 'submit'
                    ? 'Nach der Freigabe sind die Vorschau und ihre Versionshistorie öffentlich.'
                    : 'Die aktuelle Veröffentlichung wird entfernt. Bereits veröffentlichte Versionen bleiben in der Herkunftshistorie erhalten.',
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Begründung (bei Rückzug öffentlich)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bewusst bestätigen'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await run({
        'action': action,
        'id': d['id'],
        'version': d['version'],
        'reason': reason.text,
        'confirmed': true,
      });
    }
    reason.dispose();
  }

  Future<void> edit([Map<String, dynamic>? d]) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _ContributionEditor(
          session: widget.session,
          existing: d,
          manufacturer: manufacturer,
        ),
      ),
    );
    if (result != null && mounted) await run(result);
  }

  Future<void> history(Map<String, dynamic> d) async {
    try {
      final result = await api.request('POST', 'contributions', {
        'action': 'history',
        'id': d['id'],
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Beitragshistorie'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in result['entries'] as List)
                    ListTile(
                      title: Text(
                        'Revision ${e['version']} · ${contributionStates[e['state']]}',
                      ),
                      subtitle: Text('${e['updatedAt']}\n${e['reason']}'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Meine Katalogbeiträge'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Neu laden',
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Von deiner Bibliothek in den öffentlichen Katalog',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Wähle die Daten bewusst aus. Private Notizen, Projekte, lokale Referenzen und interne Herkunftsketten werden nicht übernommen. Jeder Beitrag wird vor Veröffentlichung moderiert.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('Öffentlichen Entwurf erstellen'),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Noch keine Beiträge. Deine privaten Artikel bleiben unverändert.',
                ),
              ),
            for (final raw in rows)
              Builder(
                builder: (_) {
                  final d = raw as Map<String, dynamic>;
                  final p = d['payload'] as Map;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['articleNumber']} · ${p['name']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${contributionStates[d['state']]} · ${d['source'] == 'manufacturer' ? d['manufacturerName'] : 'User-Upload'} · ${p['license']}',
                          ),
                          Text(
                            'Herkunft: ${p['origin']}\nNamensnennung: ${p['attribution']}',
                          ),
                          if (d['published'] != null &&
                              d['state'] != 'published')
                            const Text(
                              'Die vorherige freigegebene Version bleibt öffentlich, bis du sie zurückziehst.',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (d['state'] != 'review')
                                TextButton(
                                  onPressed: busy ? null : () => edit(d),
                                  child: const Text('Vorschau / bearbeiten'),
                                ),
                              if (d['state'] == 'draft')
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => transition(d, 'submit'),
                                  child: const Text('Zur Prüfung einreichen'),
                                ),
                              if (d['state'] != 'withdrawn')
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => transition(d, 'withdraw'),
                                  child: const Text('Zurückziehen'),
                                ),
                              TextButton(
                                onPressed: () => history(d),
                                child: const Text('Historie'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _ContributionEditor extends StatefulWidget {
  const _ContributionEditor({
    required this.session,
    this.existing,
    this.manufacturer,
  });
  final Session session;
  final Map<String, dynamic>? existing, manufacturer;
  @override
  State<_ContributionEditor> createState() => _EditorState();
}

class _EditorState extends State<_ContributionEditor> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'articleNumber',
      'name',
      'origin',
      'attribution',
      'reason',
    ])
      key: TextEditingController(),
  };
  final nums = {
    for (final key in [
      'widthMm',
      'heightMm',
      'depthMm',
      'voltageV',
      'currentA',
      'powerLossW',
    ])
      key: TextEditingController(),
  };
  final conditions = TextEditingController();
  List<dynamic> articles = [];
  String source = 'userUpload', license = 'CC-BY-4.0';
  bool rights = false, includeTechnical = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d == null &&
        widget.session.role == UserRole.admin &&
        widget.manufacturer?['active'] == true) {
      source = 'manufacturer';
    }
    if (d != null) {
      source = d['source'] as String;
      apply(d['payload'] as Map);
      includeTechnical = true;
    }
    loadArticles();
  }

  void apply(Map p) {
    for (final e in fields.entries) {
      if (e.key != 'reason') e.value.text = p[e.key]?.toString() ?? '';
    }
    if (['CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-4.0'].contains(p['license'])) {
      license = p['license'] as String;
    }
    final layers = p['layers'] as Map? ?? {};
    for (final layer in layers.values) {
      if (layer is Map) {
        for (final e in nums.entries) {
          if (layer.containsKey(e.key)) {
            e.value.text = layer[e.key]?.toString() ?? '';
          }
        }
      }
    }
    conditions.text =
        (layers['thermal'] as Map?)?['conditions']?.toString() ?? '';
  }

  Future<void> loadArticles() async {
    final api = WorkspaceApi(widget.session);
    try {
      final d = await api.request('GET', 'articles');
      if (mounted) {
        setState(
          () => articles = (d['articles'] ?? d['results'] ?? []) as List,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      api.close();
    }
  }

  @override
  void dispose() {
    for (final c in [...fields.values, ...nums.values, conditions]) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate() || !rights) {
      setState(() => error = 'Pflichtfelder und Rechtebestätigung prüfen.');
      return;
    }
    final payload = <String, dynamic>{
      for (final e in fields.entries)
        if (e.key != 'reason') e.key: e.value.text,
      'license': license,
    };
    if (includeTechnical) {
      payload['layers'] = {
        for (final e in {
          'mechanical': ['widthMm', 'heightMm', 'depthMm'],
          'electrical': ['voltageV', 'currentA'],
          'thermal': ['powerLossW'],
        }.entries)
          e.key: {
            for (final k in e.value)
              k: nums[k]!.text.trim().isEmpty
                  ? null
                  : num.parse(nums[k]!.text.replaceAll(',', '.')),
            if (e.key == 'thermal') 'conditions': conditions.text,
          },
      };
    }
    final d = widget.existing;
    Navigator.pop(context, {
      'action': d == null ? 'create' : 'edit',
      'source': source,
      'payload': payload,
      'rightsConfirmed': true,
      if (d != null) ...{
        'id': d['id'],
        'version': d['version'],
        'reason': fields['reason']!.text,
      },
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Öffentliche Vorschau')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Nur die folgenden Felder werden weitergegeben. Prüfe Herkunft, Namensnennung und Lizenz auch bei abgeleiteten Artikeln. Eine neue Lizenzwahl ersetzt keine Rechte am Original.',
              ),
              if (widget.existing == null)
                DropdownButtonFormField<String>(
                  initialValue: source,
                  decoration: const InputDecoration(
                    labelText: 'Katalogbereich',
                  ),
                  items: [
                    if (widget.session.role != UserRole.admin ||
                        widget.manufacturer?['active'] != true)
                      const DropdownMenuItem(
                        value: 'userUpload',
                        child: Text('User-Upload'),
                      ),
                    if (widget.session.role == UserRole.admin &&
                        widget.manufacturer?['active'] == true)
                      DropdownMenuItem(
                        value: 'manufacturer',
                        child: Text(
                          'Hersteller: ${widget.manufacturer!['name']}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => source = v!),
                ),
              if (articles.isNotEmpty && widget.existing == null)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText:
                        'Optional: Artikelnummer und Bezeichnung übernehmen',
                  ),
                  items: [
                    for (final a in articles)
                      DropdownMenuItem(
                        value: a['id'] as String,
                        child: Text(
                          '${a['articleNumber']} · ${a['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    final a = articles.firstWhere((a) => a['id'] == id);
                    setState(() {
                      fields['articleNumber']!.text =
                          a['articleNumber'] as String;
                      fields['name']!.text = a['name'] as String;
                    });
                  },
                ),
              for (final e in {
                'articleNumber': 'Artikelnummer',
                'name': 'Bezeichnung',
                'origin': 'Öffentliche Herkunft / Quellenangabe',
                'attribution': 'Öffentliche Namensnennung',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: fields[e.key],
                    decoration: InputDecoration(labelText: e.value),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Erforderlich' : null,
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: license,
                decoration: const InputDecoration(labelText: 'Datenlizenz'),
                items: [
                  for (final l in ['CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-4.0'])
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => setState(() => license = v!),
              ),
              SwitchListTile(
                title: const Text('Technische Werte bewusst mitgeben'),
                subtitle: const Text(
                  'Unbekannte Werte leer lassen. Keine technische Verifikation.',
                ),
                value: includeTechnical,
                onChanged: (v) => setState(() => includeTechnical = v),
              ),
              if (includeTechnical) ...[
                for (final e in {
                  'widthMm': 'Breite [mm]',
                  'heightMm': 'Höhe [mm]',
                  'depthMm': 'Tiefe [mm]',
                  'voltageV': 'Nennspannung [V]',
                  'currentA': 'Nennstrom [A]',
                  'powerLossW': 'Verlustleistung [W]',
                }.entries)
                  TextFormField(
                    controller: nums[e.key],
                    decoration: InputDecoration(labelText: e.value),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = num.tryParse(v.replaceAll(',', '.'));
                      return n == null || !n.isFinite || n < 0 || n > 1e9
                          ? 'Nicht negative Zahl erforderlich'
                          : null;
                    },
                  ),
                TextField(
                  controller: conditions,
                  decoration: const InputDecoration(
                    labelText: 'Öffentliche thermische Bedingungen',
                  ),
                ),
              ],
              if (widget.existing != null)
                TextFormField(
                  controller: fields['reason'],
                  decoration: const InputDecoration(
                    labelText: 'Änderungsgrund',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Erforderlich' : null,
                ),
              CheckboxListTile(
                value: rights,
                onChanged: (v) => setState(() => rights = v!),
                title: const Text(
                  'Ich darf diese Daten unter der gewählten Lizenz öffentlich weitergeben und habe private Angaben entfernt.',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: save,
                child: const Text('Als Entwurf speichern'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
