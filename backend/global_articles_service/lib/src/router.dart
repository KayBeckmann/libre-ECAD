import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'repository.dart';
import 'models.dart';

/// M1.2 — nur lesende Endpunkte, siehe Roadmap: "Keine öffentliche
/// Upload-Funktion, kein Hersteller-Verifikationsversprechen, keine
/// Replikation/Failover-Versprechen."
class ArticleRouter {
  ArticleRouter({required this.repository});
  final ArticleRepository repository;

  Router get handler {
    final router = Router();
    router.get('/health', (Request request) => healthResponse());
    router.get('/articles', _search);
    router.get('/articles/<id>', _findById);
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
    return jsonOk({'results': results.map((a) => a.toJson()).toList()});
  }

  Future<Response> _findById(Request request, String id) async {
    final article = await repository.findById(id);
    if (article == null)
      return jsonError('Artikel $id nicht gefunden.', status: 404);
    return jsonOk(article.toJson());
  }
}
