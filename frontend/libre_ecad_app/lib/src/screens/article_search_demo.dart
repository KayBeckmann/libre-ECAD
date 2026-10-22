import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session_service.dart';

/// M1.4 — "Eine globale Artikel-Suchprobe darf lediglich
/// demonstrieren, dass der separate Dienst erreichbar ist; kein
/// Artikel-/Projekt-/Zeicheneditor." Bewusst minimal.
class ArticleSearchDemo extends StatefulWidget {
  const ArticleSearchDemo({super.key, required this.globalArticlesUrl});
  final String globalArticlesUrl;

  @override
  State<ArticleSearchDemo> createState() => _ArticleSearchDemoState();
}

class _ArticleSearchDemoState extends State<ArticleSearchDemo> {
  final _queryCtrl = TextEditingController();
  List<GlobalArticleSearchHit>? _results;
  String? _error;
  bool _busy = false;

  Future<void> _search() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<SessionService>().globalArticlesApiFor(Uri.parse(widget.globalArticlesUrl));
      final results = await api.search(query);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Globale Artikelsuche (Demo)', style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Zeigt nur, dass der separate globale Artikel-Dienst erreichbar ist — '
              'kein Editor.',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    decoration: const InputDecoration(labelText: 'Artikelnummer/Bezeichnung'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : _search, child: const Text('Suchen')),
              ],
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_results != null)
              for (final hit in _results!)
                ListTile(
                  dense: true,
                  title: Text('${hit.articleNumber} — ${hit.name}'),
                  subtitle: Text(
                    hit.manufacturerName != null ? '${hit.source} · ${hit.manufacturerName}' : hit.source,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
