import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'repository.dart';
import 'models.dart';
import 'contributions/catalog.dart';

/// M1.2 — nur lesende Endpunkte, siehe Roadmap: "Keine öffentliche
/// Upload-Funktion, kein Hersteller-Verifikationsversprechen, keine
/// Replikation/Failover-Versprechen."
class ArticleRouter {
  ArticleRouter({
    required this.repository,
    this.catalog,
    this.internalToken = '',
  });
  final ContributionCatalog? catalog;
  final String internalToken;
  final ArticleRepository repository;

  Router get handler {
    final router = Router();
    router.get('/health', (Request request) => healthResponse());
    router.get('/articles', _search);
    router.get('/articles/<id>', _findById);
    router.get(
      '/articles/<id>/history',
      (Request r, String id) => apiGuard(
        () async => jsonOk({'entries': await catalog?.publicHistory(id) ?? []}),
      ),
    );
    router.post(
      '/internal/contributions',
      (Request r) => apiGuard(() async {
        if (internalToken.isEmpty ||
            r.headers['x-internal-token'] != internalToken)
          return jsonError('Nicht berechtigt.', status: 403);
        final b = await readJson(r);
        if (catalog == null) return jsonError('Nicht verfügbar.', status: 503);
        Json result;
        if (b['mode'] == 'operator') {
          result = await catalog!.operator(b);
        } else {
          if (b['actor'] is! Json) return jsonError('Akteur erforderlich.');
          result = await catalog!.user(b['actor'] as Json, b);
        }
        if (result['payload'] is Map)
          result['duplicates'] = await catalog!.duplicates(
            (result['payload'] as Map)['articleNumber'] as String,
          );
        return jsonOk(result);
      }),
    );
    return router;
  }

  Future<Response> _search(Request request) async {
    final query = request.url.queryParameters['query'] ?? '';
    if (query.trim().isEmpty) {
      return jsonError(
        'query ist Pflicht (Artikelnummer oder Bezeichnung, auch Teilstring).',
      );
    }
    final source = request.url.queryParameters['source'];
    final manufacturer = request.url.queryParameters['manufacturer'];
    if (source != null &&
        !['general', 'manufacturer', 'userUpload'].contains(source)) {
      return jsonError('Unbekannter Artikelbereich.');
    }
    final results = (await repository.search(query)).where(
      (article) =>
          (source == null || article.source.wireValue == source) &&
          (manufacturer == null ||
              manufacturer.trim().isEmpty ||
              (article.manufacturerName ?? '').toLowerCase() ==
                  manufacturer.trim().toLowerCase()),
    );
    final published = (await catalog?.publicArticles() ?? []).where(
      (a) =>
          ('${a['articleNumber']} ${a['name']}').toLowerCase().contains(
            query.toLowerCase(),
          ) &&
          (source == null || a['source'] == source) &&
          (manufacturer == null ||
              manufacturer.trim().isEmpty ||
              (a['manufacturerName'] ?? '').toString().toLowerCase() ==
                  manufacturer.trim().toLowerCase()),
    );
    return jsonOk({
      'results': [...results.map((a) => a.toJson()), ...published],
    });
  }

  Future<Response> _findById(Request request, String id) async {
    final published = await catalog?.publicArticle(id);
    if (published != null) return jsonOk(published);
    final article = await repository.findById(id);
    if (article == null)
      return jsonError('Artikel $id nicht gefunden.', status: 404);
    return jsonOk(article.toJson());
  }
}
