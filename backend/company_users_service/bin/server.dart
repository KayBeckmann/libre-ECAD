import 'dart:io';
import 'package:company_users_service/src/operator/management.dart';
import 'package:shared_server_kit/shared_server_kit.dart';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:company_users_service/src/db/schema.dart';
import 'package:company_users_service/src/repository_postgres.dart';
import 'package:company_users_service/src/router.dart';
import 'package:company_users_service/src/db/migrations.dart';
import 'package:company_users_service/src/workspace/store.dart';
import 'package:company_users_service/src/workspace/global_catalog.dart';

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8083');

  final db = Pool<void>.withEndpoints([
    Endpoint(
      host: Platform.environment['DB_HOST'] ?? 'localhost',
      port: int.parse(Platform.environment['DB_PORT'] ?? '5432'),
      database: Platform.environment['DB_NAME'] ?? 'company_users',
      username: Platform.environment['DB_USER'] ?? 'company_users',
      password: Platform.environment['DB_PASSWORD'] ?? 'company_users',
    ),
    ], settings: PoolSettings(sslMode: SslMode.disable, maxConnectionCount: 8),
  );
  await ensureSchema(db);
  await migrateWorkspace(db);
  await migrateManagement(db);

  final internalToken = Platform.environment['INTERNAL_SERVICE_TOKEN'] ?? '';
  if (internalToken.isEmpty) {
    stderr.writeln(
      'WARNUNG: INTERNAL_SERVICE_TOKEN ist leer — /internal/* ist damit für '
      'niemanden nutzbar (siehe _hasValidInternalToken).',
    );
  }

  final repository = PostgresCompanyUserRepository(db);
  final router = CompanyUserRouter(
    repository: repository,
    internalToken: internalToken,
    operatorHandler: ManagedCompanies(db,internalToken).handle,
    catalogApi: InternalApi(Uri.parse(Platform.environment['GLOBAL_ARTICLES_SERVICE_URL']??'http://global-articles-service:8082'), internalToken),
    workspace: PostgresWorkspaceStore(db),
    globalLookup: GlobalCatalog(
      Uri.parse(
        Platform.environment['GLOBAL_ARTICLES_SERVICE_URL'] ??
            'http://global-articles-service:8082',
      ),
    ).find,
  );
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.handler.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('company-users-service läuft auf Port ${server.port}');
}
