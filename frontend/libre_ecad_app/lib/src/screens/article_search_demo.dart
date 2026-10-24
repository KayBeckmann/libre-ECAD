import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/workspace_api.dart';
import '../models.dart';
import '../session_service.dart';

/// Separate global catalog search. Its failure never clears local libraries.
class ArticleSearchDemo extends StatefulWidget {
  const ArticleSearchDemo({super.key, required this.globalArticlesUrl});
  final String globalArticlesUrl;
  @override
  State<ArticleSearchDemo> createState() => _ArticleSearchDemoState();
}

class _ArticleSearchDemoState extends State<ArticleSearchDemo> {
  final query = TextEditingController();
  final manufacturer = TextEditingController();
  String source = 'general';
  List<GlobalArticleSearchHit>? results;
  String? error;
  bool busy = false;
  static const labels = {
    'general': 'Allgemeine Artikel',
    'manufacturer': 'Hersteller',
    'userUpload': 'User-Uploads',
  };
  @override
  void dispose() {
    query.dispose();
    manufacturer.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (query.text.trim().isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      results = null;
    });
    try {
      final api = context.read<SessionService>().globalArticlesApiFor(
        Uri.parse(widget.globalArticlesUrl),
      );
      final hits = await api.search(
        query.text.trim(),
        source: source,
        manufacturer: source == 'manufacturer'
            ? manufacturer.text.trim()
            : null,
      );
      if (mounted) {
        setState(() => results = hits);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Globaler Katalog nicht verfügbar: $e. Die lokale Artikelbibliothek bleibt unverändert.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> copy(GlobalArticleSearchHit hit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Persönliche Artikelkopie'),
        content: Text(
          '${hit.articleNumber} · ${hit.name}\nVersion ${hit.version}\n\nSynthetische Beispieldaten: Lizenz und technische Angaben sind ungeklärt. Die Kopie wird als ungeprüft angelegt und bleibt unabhängig vom globalen Original.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bewusst übernehmen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final api = WorkspaceApi(context.read<SessionService>().session!);
    try {
      await api.request(
        'POST',
        'global-articles/${Uri.encodeComponent(hit.id)}/copy',
        {'scope': 'personal', 'version': hit.version},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kopie im persönlichen Artikelstamm angelegt.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Globaler Artikelkatalog',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Synthetische Beispieldaten · Herkunft ist keine Herstellerverifikation.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: source,
            decoration: const InputDecoration(labelText: 'Katalogbereich'),
            items: [
              for (final e in labels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    source = v!;
                    results = null;
                    error = null;
                  }),
          ),
          if (source == 'manufacturer')
            TextField(
              controller: manufacturer,
              decoration: const InputDecoration(
                labelText: 'Hersteller (exakt, z. B. ACME; leer = alle)',
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: query,
                  decoration: const InputDecoration(
                    labelText: 'Artikelnummer / Bezeichnung',
                  ),
                  onSubmitted: (_) => search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : search,
                child: const Text('Suchen'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (results != null && results!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Keine Treffer in diesem Bereich.'),
            ),
          if (results != null)
            for (final hit in results!)
              ListTile(
                title: Text('${hit.articleNumber} · ${hit.name}'),
                subtitle: Text(
                  '${labels[hit.source]}${hit.manufacturerName == null ? '' : ' / ${hit.manufacturerName}'} · Version ${hit.version}',
                ),
                trailing: IconButton(
                  tooltip: 'In persönlichen Stamm kopieren',
                  onPressed: () => copy(hit),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
        ],
      ),
    ),
  );
}
