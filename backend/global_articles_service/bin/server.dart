import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:global_articles_service/src/db/schema.dart';
import 'package:global_articles_service/src/repository_postgres.dart';
import 'package:global_articles_service/src/router.dart';
import 'package:global_articles_service/src/seed_data.dart';

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8082');

  final db = await Connection.open(
    Endpoint(
      host: Platform.environment['DB_HOST'] ?? 'localhost',
      port: int.parse(Platform.environment['DB_PORT'] ?? '5432'),
      database: Platform.environment['DB_NAME'] ?? 'global_articles',
      username: Platform.environment['DB_USER'] ?? 'global_articles',
      password: Platform.environment['DB_PASSWORD'] ?? 'global_articles',
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );
  await ensureSchema(db);

  final repository = PostgresArticleRepository(db);
  if (await repository.isEmpty()) {
    await repository.insertAll(buildSeedArticles());
    stdout.writeln('Testdaten (Beispielartikel) eingespielt.');
  }

  final router = ArticleRouter(repository: repository);
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.handler.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('global-articles-service läuft auf Port ${server.port}');
}
