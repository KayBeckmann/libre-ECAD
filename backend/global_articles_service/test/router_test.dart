import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'package:global_articles_service/src/models.dart';
import 'package:global_articles_service/src/repository_memory.dart';
import 'package:global_articles_service/src/router.dart';
import 'package:global_articles_service/src/seed_data.dart';

void main() {
  late InMemoryArticleRepository repository;
  late HttpServer server;
  late Uri baseUrl;

  setUp(() async {
    repository = InMemoryArticleRepository();
    await repository.insertAll(buildSeedArticles());
    final router = ArticleRouter(repository: repository);
    server = await shelf_io.serve(router.handler.call, 'localhost', 0);
    baseUrl = Uri.parse('http://localhost:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('GET /health ist erreichbar', () async {
    final response = await http.get(baseUrl.resolve('/health'));
    expect(response.statusCode, 200);
  });

  test(
    'Suche ohne query liefert einen verständlichen Fehler statt leerer Liste',
    () async {
      final response = await http.get(baseUrl.resolve('/articles'));
      expect(response.statusCode, 400);
    },
  );

  test(
    'Suche nach Artikelnummer findet Testtreffer aus allen drei Bereichen mit korrekter '
    'Herkunft/Version',
    () async {
      final response = await http.get(baseUrl.resolve('/articles?query=ALLG'));
      expect(response.statusCode, 200);
      final results =
          (jsonDecode(response.body) as Map<String, Object?>)['results']
              as List;
      expect(results, hasLength(2));
      for (final r in results) {
        expect((r as Map<String, Object?>)['source'], 'general');
      }
    },
  );

  test(
    'Suche nach Hersteller-Artikelnummer zeigt den zugeordneten Hersteller',
    () async {
      final response = await http.get(baseUrl.resolve('/articles?query=ACME'));
      final results =
          (jsonDecode(response.body) as Map<String, Object?>)['results']
              as List;
      expect(results, hasLength(1));
      final hit = results.single as Map<String, Object?>;
      expect(hit['source'], 'manufacturer');
      expect(hit['manufacturerName'], 'ACME');
      expect(hit['version'], 1);
    },
  );

  test('Suche nach Bezeichnung findet den User-Upload-Testartikel', () async {
    final response = await http.get(
      baseUrl.resolve('/articles?query=Community'),
    );
    final results =
        (jsonDecode(response.body) as Map<String, Object?>)['results'] as List;
    expect(results, hasLength(1));
    expect((results.single as Map<String, Object?>)['source'], 'userUpload');
  });

  test('GET /articles/<id> liefert 404 für unbekannte ID', () async {
    final response = await http.get(baseUrl.resolve('/articles/unbekannt'));
    expect(response.statusCode, 404);
  });

  test(
    'ArticleSource.fromWire wirft bei unbekanntem Wert statt still null zu liefern',
    () {
      expect(
        () => ArticleSourceJson.fromWire('does-not-exist'),
        throwsArgumentError,
      );
    },
  );
  test(
    'source and exact manufacturer filters keep catalog areas separate',
    () async {
      final response = await http.get(
        baseUrl.resolve(
          '/articles?query=Beispieldaten&source=manufacturer&manufacturer=acme',
        ),
      );
      final results = jsonDecode(response.body)['results'] as List;
      expect(results, hasLength(1));
      expect(results.single['manufacturerName'], 'ACME');
      final user = await http.get(
        baseUrl.resolve('/articles?query=Beispieldaten&source=userUpload'),
      );
      expect(
        (jsonDecode(user.body)['results'] as List).single['source'],
        'userUpload',
      );
      expect(
        (await http.get(
          baseUrl.resolve('/articles?query=Test&source=personal'),
        )).statusCode,
        400,
      );
    },
  );
}
