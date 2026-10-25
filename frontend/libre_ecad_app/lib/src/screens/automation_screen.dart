import 'package:flutter/material.dart';
import 'package:ecad_core/ecad_core.dart';

import '../api/workspace_api.dart';
import '../models.dart';
import '../drawing/drawing_comparison.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({
    super.key,
    required this.session,
    required this.projectId,
  });
  final Session session;
  final String projectId;
  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  late final api = WorkspaceApi(widget.session);
  Json? review;
  List<Json> tokens = [];
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

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final r = await api.request('GET', 'automation/review/${widget.projectId}');
    final t = await api.request('GET', 'automation/tokens');
    if (mounted) {
      setState(() {
        review = r;
        tokens = (t['tokens'] as List).cast<Json>();
      });
    }
  }

  Future<void> load() => run(refresh);
  Future<void> issue() async {
    final label = TextEditingController();
    bool proposals = false, consent = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('API-/MCP-Zugang erstellen'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Dieser Zugang darf dieses Projekt acht Stunden lesen. Wähle selbst, welchem Programm oder Modellanbieter du ihn gibst. Dessen Umgang mit Projektdaten prüfst du vor der Weitergabe. LibreECAD verbindet sich hier mit keinem Modellanbieter.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: label,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung, z. B. lokale Assistenz',
                    ),
                  ),
                  CheckboxListTile(
                    value: proposals,
                    onChanged: (v) => update(() => proposals = v!),
                    title: const Text('Zeichnungsvorschläge erlauben'),
                    subtitle: const Text(
                      'Übernahme und Freigabe bleiben in der Oberfläche.',
                    ),
                  ),
                  CheckboxListTile(
                    value: consent,
                    onChanged: (v) => update(() => consent = v!),
                    title: const Text(
                      'Datenzugriff auf dieses Projekt bewusst erlauben',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: consent ? () => Navigator.pop(c, true) : null,
              child: const Text('Zugang erstellen'),
            ),
          ],
        ),
      ),
    );
    final name = label.text.trim();
    Future.delayed(const Duration(milliseconds: 350), label.dispose);
    if (accepted != true || !mounted) return;
    await run(() async {
      final t = await api.request('POST', 'automation/tokens', {
        'confirmed': true,
        'projectIds': [widget.projectId],
        'label': name,
        'allowProposals': proposals,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Zugang einmalig kopieren'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nur im gewählten MCP-Client als ECAD_API_TOKEN hinterlegen. Der Klartext wird nach Schließen nicht erneut angezeigt.',
                ),
                const SizedBox(height: 16),
                SelectableText(t['token']),
                const SizedBox(height: 16),
                SelectableText(
                  'ECAD_BACKEND_URL=${widget.session.backendUrl}\nGültig bis ${t['expiresAt']}',
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
      await refresh();
    });
  }

  Future<void> compare(Json proposal) async {
    final current = review!['project'] as Json;
    final stale = proposal['baseVersion'] != current['version'];
    final changes = drawingChanges(
      current['drawing'] as Json? ?? emptyDrawing(),
      proposal['drawing'],
    );
    final accept = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Vorschlag prüfen · ${changes.length} Änderungen'),
        content: SizedBox(
          width: 1100,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Begründung: ${proposal['reason']}'),
              Text(
                'Basis V${proposal['baseVersion']} · Server V${current['version']} · vorgeschlagen durch ${proposal['proposedBy']}',
              ),
              if (stale)
                const Text(
                  'Überholt: neuen Vorschlag auf aktuellem Stand erstellen lassen.',
                ),
              const Text(
                'Übernahme erstellt einen Arbeitsstand. Sie erteilt keine fachliche Freigabe.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DrawingComparison(
                  left: current['drawing'] as Json? ?? emptyDrawing(),
                  right: proposal['drawing'],
                  leftTitle: 'Aktueller Serverstand',
                  rightTitle: 'Vorgeschlagener Stand',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed:
                stale ||
                    proposal['status'] == 'applied' ||
                    MediaQuery.sizeOf(c).width < 1000 ||
                    MediaQuery.sizeOf(c).height -
                            kToolbarHeight -
                            MediaQuery.paddingOf(c).vertical <
                        500
                ? null
                : () => Navigator.pop(c, true),
            child: const Text('Verglichen · Vorschlag übernehmen'),
          ),
        ],
      ),
    );
    if (accept != true || !mounted) return;
    await run(() async {
      await api.request(
        'POST',
        'automation/review/${widget.projectId}/${proposal['id']}/apply',
        {'confirmed': true, 'version': current['version']},
      );
      await refresh();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('API / MCP'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Text(
          review?['project']['name'] ?? 'Projekt laden',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Projektbezogene Zugänge und Zeichnungsvorschläge. Keine automatische Freigabe oder Konfliktauflösung.',
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy || review == null ? null : issue,
            icon: const Icon(Icons.key),
            label: const Text('Zugang für dieses Projekt erstellen'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Meine Zugänge', style: Theme.of(context).textTheme.titleLarge),
        for (final t in tokens.where(
          (t) => (t['projectIds'] as List).contains(widget.projectId),
        ))
          ListTile(
            title: Text(t['label']),
            subtitle: Text(
              '${t['allowProposals'] == true ? "Lesen und Vorschläge" : "Nur lesen"} · bis ${t['expiresAt']}',
            ),
            trailing: t['revoked'] == true
                ? const Text('Widerrufen')
                : TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await api.request(
                              'POST',
                              'automation/tokens/${t['id']}/revoke',
                              {},
                            );
                            await refresh();
                          }),
                    child: const Text('Widerrufen'),
                  ),
          ),
        const SizedBox(height: 24),
        Text(
          'Zeichnungsvorschläge',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (review != null && (review!['proposals'] as List).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Noch keine Vorschläge.'),
          ),
        for (final p in (review?['proposals'] as List? ?? []).cast<Json>())
          ListTile(
            title: Text(p['reason']),
            subtitle: Text(
              'Basis V${p['baseVersion']} · ${switch (p['status']) {
                'applied' => 'Übernommen',
                'stale' => 'Überholt',
                _ => 'Wartet auf Prüfung',
              }}',
            ),
            trailing: const Icon(Icons.compare_arrows),
            onTap: busy ? null : () => compare(p),
          ),
      ],
    ),
  );
}
