import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session_service.dart';
import 'article_search_demo.dart';

import 'package:ecad_core/ecad_core.dart';

import 'symbol_designer.dart';

import '../api/workspace_api.dart';
import '../models.dart';
import '../article_presentation.dart';

class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({super.key, required this.session});
  final Session session;
  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  late final api = WorkspaceApi(widget.session);
  final query = TextEditingController();
  String scope = 'personal';
  late Future<Map<String, dynamic>> data = load();
  late final globalUrl = context.read<SessionService>().loadGlobalArticlesUrl();
  bool symbolsOnly = false;
  Future<Map<String, dynamic>> load() => api.request(
    'GET',
    'articles?scope=$scope&query=${Uri.encodeQueryComponent(query.text)}',
  );
  void reload() => setState(() => data = load());
  @override
  void dispose() {
    query.dispose();
    api.close();
    super.dispose();
  }

  Future<void> open([Map<String, dynamic>? article]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleEditor(
          session: widget.session,
          scope: scope,
          article: article,
        ),
      ),
    );
    if (changed == true && mounted) {
      reload();
    }
  }

  Future<void> copy(Map<String, dynamic> a) async {
    final target = scope == 'personal' ? 'company' : 'personal';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artikel bewusst kopieren'),
        content: Text(
          '„${a['name']}“ Version ${a['version']} in den ${target == 'company' ? 'Firmenstamm' : 'persönlichen Stamm'} übernehmen?\n\nDie Kopie erhält eine eigene ID. Spätere Änderungen werden nicht automatisch übertragen. Herkunft und Lizenz bleiben nachvollziehbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kopie anlegen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await api.request('POST', 'articles/${a['id']}/copy', {
        'scope': target,
        'version': a['version'],
      });
      if (mounted) {
        setState(() => scope = target);
        reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Artikelbibliothek')),
    floatingActionButton:
        scope != 'global' &&
            (scope == 'personal' || widget.session.role == UserRole.admin)
        ? FloatingActionButton.extended(
            onPressed: () => open(),
            icon: const Icon(Icons.add),
            label: const Text('Artikel anlegen'),
          )
        : null,
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'personal',
                      label: Text('Persönlich'),
                      icon: Icon(Icons.person_outline),
                    ),
                    ButtonSegment(
                      value: 'company',
                      label: Text('Firma'),
                      icon: Icon(Icons.business_outlined),
                    ),
                    ButtonSegment(
                      value: 'global',
                      label: Text('Global'),
                      icon: Icon(Icons.public),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) {
                    setState(() => scope = s.first);
                    if (scope != 'global') reload();
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(switch (scope) {
                'personal' => 'Persönlich · nur für dich sichtbar. Eigene Artikel und unabhängige Kopien.',
                'company' => 'Firma · für Firmenmitglieder sichtbar; bearbeiten dürfen Firmenadmins.',
                _ => 'Global · nach Herkunft durchsuchen und bewusst als persönliche Kopie übernehmen.',
              }),
              if (scope != 'global') ...[
                const SizedBox(height: 12),
                FilterChip(
                  label: const Text('Nur mit Schaltsymbol'),
                  selected: symbolsOnly,
                  onSelected: (v) => setState(() => symbolsOnly = v),
                ),
                TextField(
                  controller: query,
                  onSubmitted: (_) => reload(),
                  decoration: InputDecoration(
                    labelText: 'Artikelnummer oder Bezeichnung',
                    suffixIcon: IconButton(
                      onPressed: reload,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (scope == 'global')
          Expanded(
            child: FutureBuilder<String>(
              future: globalUrl,
              builder: (context, snapshot) => snapshot.hasData
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ArticleSearchDemo(
                        globalArticlesUrl: snapshot.data!,
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          )
        else
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: data,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(child: Text('${s.error}'));
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final articles =
                    (s.data!['articles'] as List)
                        .where(
                          (a) =>
                              !symbolsOnly ||
                              a['layers']?['symbol']?['definition'] != null,
                        )
                        .toList()
                      ..sort(
                        (a, b) => a['articleNumber'].toString().compareTo(
                          b['articleNumber'].toString(),
                        ),
                      );
                if (articles.isEmpty) {
                  return const Center(
                    child: Text('Keine Artikel in diesem Bereich.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                  itemCount: articles.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final a = articles[i] as Map<String, dynamic>;
                    return ListTile(
                      leading: Icon(
                        a['layers']?['symbol']?['definition'] != null
                            ? Icons.polyline
                            : Icons.inventory_2_outlined,
                      ),
                      isThreeLine: true,
                      title: Text('${a['articleNumber']} · ${a['name']}'),
                      subtitle: Text(
                        "${scope == 'personal' ? 'Persönlich' : 'Firma'} · V${a['version']} · ${a['layers']?['symbol']?['definition'] != null ? 'Schaltsymbol vorhanden' : 'Ohne Schaltsymbol'}\n${a['origin']} · Lizenz: ${a['license']} · ungeprüft",
                      ),
                      onTap: () => open(a),
                      trailing:
                          scope == 'company' ||
                              widget.session.role == UserRole.admin
                          ? IconButton(
                              tooltip: scope == 'personal'
                                  ? 'In Firmenstamm übernehmen'
                                  : 'Persönliche Kopie',
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: () => copy(a),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
      ],
    ),
  );
}

class ArticleEditor extends StatefulWidget {
  const ArticleEditor({
    super.key,
    required this.session,
    required this.scope,
    this.article,
  });
  final Session session;
  final String scope;
  final Map<String, dynamic>? article;
  @override
  State<ArticleEditor> createState() => _ArticleEditorState();
}

class _ArticleEditorState extends State<ArticleEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late final api = WorkspaceApi(widget.session);
  Json? definition;
  bool busy = false;
  String? error;
  bool get writable =>
      widget.scope == 'personal' || widget.session.role == UserRole.admin;
  @override
  void initState() {
    super.initState();
    final a = widget.article ?? {};
    for (final key in ['articleNumber', 'name', 'origin', 'license', 'notes']) {
      fields[key] = TextEditingController(text: a[key] as String? ?? '');
    }
    final layers = a['layers'] as Map? ?? {};
    final saved = (layers['symbol'] as Map?)?['definition'];
    if (saved != null) definition = cloneJson(saved as Json);
    for (final entry in {
      'symbol': ['reference', 'license'],
      'mechanical': ['widthMm', 'heightMm', 'depthMm', 'viewReference'],
      'electrical': ['voltageV', 'currentA'],
      'thermal': ['powerLossW', 'conditions'],
    }.entries) {
      final layer = layers[entry.key] as Map? ?? {};
      for (final key in entry.value) {
        fields['${entry.key}.$key'] = TextEditingController(
          text: layer[key]?.toString() ?? '',
        );
      }
    }
    final terminals = (layers['symbol'] as Map?)?['terminals'] as List? ?? [];
    fields['terminals'] = TextEditingController(
      text: terminals.map((t) => '${t['id']};${t['label']}').join('\n'),
    );
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    api.close();
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool required = false,
    bool number = false,
    int lines = 1,
    int max = 200,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: fields[key],
      readOnly: !writable,
      decoration: InputDecoration(
        labelText: label,
        helperText: number
            ? 'Leer = unbekannt; Wert in angegebener Einheit'
            : null,
      ),
      maxLines: lines,
      maxLength: max,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'Pflichtfeld';
        }
        if (number && v != null && v.trim().isNotEmpty) {
          final n = double.tryParse(v.replaceAll(',', '.'));
          if (n == null || !n.isFinite || n < 0 || n > 1e9) {
            return 'Nicht negative, endliche Zahl erforderlich.';
          }
        }
        return null;
      },
    ),
  );
  Widget section(String title, String note, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(note),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
  Map<String, dynamic> body() {
    final layers = <String, dynamic>{};
    for (final entry in {
      'symbol': ['reference', 'license'],
      'mechanical': ['widthMm', 'heightMm', 'depthMm', 'viewReference'],
      'electrical': ['voltageV', 'currentA'],
      'thermal': ['powerLossW', 'conditions'],
    }.entries) {
      layers[entry.key] = <String, dynamic>{};
      for (final key in entry.value) {
        final text = fields['${entry.key}.$key']!.text.trim();
        final numeric = [
          'widthMm',
          'heightMm',
          'depthMm',
          'voltageV',
          'currentA',
          'powerLossW',
        ].contains(key);
        layers[entry.key][key] = numeric
            ? (text.isEmpty ? null : double.parse(text.replaceAll(',', '.')))
            : text;
      }
    }
    layers['symbol']['terminals'] = [
      for (final line
          in fields['terminals']!.text
              .split('\n')
              .where((l) => l.trim().isNotEmpty))
        {
          'id': line.split(';').first.trim(),
          'label': line.contains(';')
              ? line.substring(line.indexOf(';') + 1).trim()
              : line.trim(),
        },
    ];
    if (definition != null) layers['symbol']['definition'] = definition;
    return {
      for (final key in ['articleNumber', 'name', 'origin', 'license', 'notes'])
        key: fields[key]!.text.trim(),
      'scope': widget.scope,
      'layers': layers,
      if (widget.article != null) 'version': widget.article!['version'],
    };
  }

  Future<void> designSymbol() async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => SymbolDesigner(initial: definition, editable: writable),
      ),
    );
    if (result == null || !mounted || !writable) return;
    setState(() {
      definition = result;
      fields['symbol.reference']!.text = result['name'];
      fields['terminals']!.text = (result['ports'] as List)
          .map((p) => '${p['id']};${p['label']}')
          .join('\n');
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.request(
        widget.article == null ? 'POST' : 'PATCH',
        widget.article == null
            ? 'articles'
            : 'articles/${widget.article!['id']}',
        body(),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> history() async {
    try {
      final data = await api.request(
        'GET',
        'articles/${widget.article!['id']}/history',
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Artikelversionen'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in data['versions'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Version ${v['version']} · ${v['updatedAt']}',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          SelectableText(
                            articleVersionText(v as Map<String, dynamic>),
                          ),
                        ],
                      ),
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
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.article == null
            ? 'Artikel-Baukasten'
            : '${widget.article!['name']} · V${widget.article!['version']}',
      ),
      actions: [
        if (widget.article != null)
          TextButton.icon(
            onPressed: history,
            icon: const Icon(Icons.history),
            label: const Text('Versionen'),
          ),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Ungeprüfte Artikelangaben · keine Berechnungs- oder Normfreigabe. Fehlende Werte bleiben ausdrücklich unbekannt.',
              ),
              const SizedBox(height: 16),
              if (widget.article != null) ...[
                for (final warning
                    in widget.article!['warnings'] as List? ?? [])
                  Text('• $warning'),
                const SizedBox(height: 16),
              ],
              if (widget.article?['source'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(
                    articleSourceText(widget.article!['source']),
                  ),
                ),
              section(
                'Stammdaten',
                '${widget.scope == 'personal' ? 'Persönlicher Stamm' : 'Firmenstamm'} · keine öffentliche Veröffentlichung',
                [
                  field('articleNumber', 'Artikelnummer', required: true),
                  field('name', 'Bezeichnung', required: true),
                  field(
                    'origin',
                    'Herkunft / Datenquelle',
                    required: true,
                    max: 2000,
                  ),
                  field(
                    'license',
                    'Lizenz / Nutzungsrechte (ggf. ausdrücklich ungeklärt)',
                    required: true,
                    max: 1000,
                  ),
                  field('notes', 'Notizen', lines: 3, max: 4000),
                ],
              ),
              section(
                'Schaltsymbol und Anschlüsse',
                'Referenzen und Anschluss-IDs bleiben von mechanischen und elektrischen Daten getrennt.',
                [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : designSymbol,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(
                        definition == null
                            ? 'Schaltsymbol erstellen'
                            : writable
                            ? 'Schaltsymbol bearbeiten'
                            : 'Schaltsymbol ansehen',
                      ),
                    ),
                  ),
                  if (definition != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${definition!['name']} · ${(definition!['ports'] as List).length} Anschlüsse · ${(definition!['primitives'] as List).length} Zeichenelemente',
                      ),
                    ),
                  field(
                    'symbol.reference',
                    'Symbolreferenz / eigene Symbolbezeichnung',
                    max: 2000,
                  ),
                  field('symbol.license', 'Rechte am Symbol', max: 2000),
                  field(
                    'terminals',
                    'Anschlüsse: eine Zeile je ID;Bezeichnung',
                    lines: 5,
                    max: 20000,
                  ),
                ],
              ),
              section(
                'Mechanische Ebene',
                'Maße in Millimetern; die Ansicht wird separat referenziert.',
                [
                  field('mechanical.widthMm', 'Breite [mm]', number: true),
                  field('mechanical.heightMm', 'Höhe [mm]', number: true),
                  field('mechanical.depthMm', 'Tiefe [mm]', number: true),
                  field(
                    'mechanical.viewReference',
                    'Ansichtsreferenz',
                    max: 2000,
                  ),
                ],
              ),
              section(
                'Elektrische Ebene',
                'Kenndaten sind Eingaben, keine Auslegungsberechnung.',
                [
                  field(
                    'electrical.voltageV',
                    'Nennspannung [V]',
                    number: true,
                  ),
                  field('electrical.currentA', 'Nennstrom [A]', number: true),
                ],
              ),
              section(
                'Thermische Ebene',
                'Verlustleistung ist ohne Einsatzbedingungen nicht belastbar.',
                [
                  field(
                    'thermal.powerLossW',
                    'Verlustleistung [W]',
                    number: true,
                  ),
                  field(
                    'thermal.conditions',
                    'Bedingungen / Bezug der Verlustleistung',
                    lines: 3,
                    max: 2000,
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (writable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: busy ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(busy ? 'Speichert …' : 'Artikel speichern'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
