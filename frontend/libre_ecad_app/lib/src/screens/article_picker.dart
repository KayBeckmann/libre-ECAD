import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

import '../api/workspace_api.dart';

Future<Json?> pickLocalArticle(
  BuildContext context,
  WorkspaceApi api, {
  bool symbolsOnly = false,
}) async {
  final personal = await api.request('GET', 'articles?scope=personal');
  final company = await api.request('GET', 'articles?scope=company');
  if (!context.mounted) return null;
  String query = '', scope = 'all';
  final rows = [
    ...(personal['articles'] as List),
    ...(company['articles'] as List),
  ].cast<Json>();
  return showDialog<Json>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, update) {
        final filtered = rows
            .where(
              (a) =>
                  (scope == 'all' || a['scope'] == scope) &&
                  (!symbolsOnly ||
                      a['layers']?['symbol']?['definition'] != null) &&
                  '${a['articleNumber']} ${a['name']}'.toLowerCase().contains(
                    query,
                  ),
            )
            .toList();
        return AlertDialog(
          title: Text(
            symbolsOnly
                ? 'Artikelsymbol übernehmen'
                : 'Artikelversion zuordnen',
          ),
          content: SizedBox(
            width: 650,
            height: 480,
            child: Column(
              children: [
                const Text(
                  'Globale Artikel zuerst in der Artikelbibliothek bewusst kopieren. Hier wird eine feste lokale Artikelversion gewählt.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Beide')),
                    ButtonSegment(value: 'personal', label: Text('Persönlich')),
                    ButtonSegment(value: 'company', label: Text('Firma')),
                  ],
                  selected: {scope},
                  onSelectionChanged: (v) => update(() => scope = v.single),
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Artikel suchen',
                  ),
                  onChanged: (v) =>
                      update(() => query = v.trim().toLowerCase()),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (filtered.isEmpty)
                        const ListTile(title: Text('Keine passenden Artikel.')),
                      for (final source in ['personal', 'company']) ...[
                        if (filtered.any((a) => a['scope'] == source))
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              source == 'personal' ? 'PERSÖNLICH' : 'FIRMA',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        for (final a in filtered.where(
                          (a) => a['scope'] == source,
                        ))
                          ListTile(
                            title: Text('${a['articleNumber']} · ${a['name']}'),
                            subtitle: Text('V${a['version']} · ${a['origin']}'),
                            onTap: () => Navigator.pop(c, a),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    ),
  );
}
