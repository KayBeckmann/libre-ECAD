import 'dart:io';
import 'package:super_admin_service/src/operator/console.dart';

import 'package:postgres/postgres.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:super_admin_service/src/company_provisioning_client.dart';
import 'package:super_admin_service/src/db/schema.dart';
import 'package:super_admin_service/src/repository_postgres.dart';
import 'package:super_admin_service/src/router.dart';

/// Super-Admin-Dienst (M1.1). Konfiguration ausschließlich über
/// Umgebungsvariablen — siehe `.env.example` im Repo-Root. **Keine**
/// Secrets im Code oder in Logs.
Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8081');

  final db = Pool<void>.withEndpoints([
    Endpoint(
      host: Platform.environment['DB_HOST'] ?? 'localhost',
      port: int.parse(Platform.environment['DB_PORT'] ?? '5432'),
      database: Platform.environment['DB_NAME'] ?? 'super_admin',
      username: Platform.environment['DB_USER'] ?? 'super_admin',
      password: Platform.environment['DB_PASSWORD'] ?? 'super_admin',
    ),
    ], settings: PoolSettings(sslMode: SslMode.disable, maxConnectionCount: 8),
  );
  await ensureSchema(db);

  final repository = PostgresSuperAdminRepository(db);

  // Bootstrap: erster Super-Admin aus Umgebungsvariablen, nur wenn
  // noch keiner existiert — kein hartkodiertes Passwort im Code.
  if (await repository.isEmpty()) {
    final bootstrapUsername = Platform.environment['SUPER_ADMIN_BOOTSTRAP_USERNAME'];
    final bootstrapPassword = Platform.environment['SUPER_ADMIN_BOOTSTRAP_PASSWORD'];
    if (bootstrapUsername == null || bootstrapPassword == null) {
      stderr.writeln(
        'Kein Super-Admin vorhanden und SUPER_ADMIN_BOOTSTRAP_USERNAME/'
        '_PASSWORD nicht gesetzt — Dienst startet ohne nutzbaren Zugang.',
      );
    } else {
      await repository.createSuperAdmin(
        username: bootstrapUsername,
        passwordHash: Passwords.hash(bootstrapPassword),
      );
      stdout.writeln('Bootstrap-Super-Admin "$bootstrapUsername" angelegt.');
    }
  }

  final companyClient = HttpCompanyProvisioningClient(
    baseUrl: Uri.parse(Platform.environment['COMPANY_USERS_SERVICE_URL'] ?? 'http://localhost:8083'),
    internalToken: Platform.environment['INTERNAL_SERVICE_TOKEN'] ?? '',
  );

  final records=PostgresRecords(db);
  await records.migrate();
  final token=Platform.environment['INTERNAL_SERVICE_TOKEN']??'';
  final router = SuperAdminRouter(repository: repository, companyClient: companyClient,
    console:OperatorConsole(records:records,
      companies:InternalApi(Uri.parse(Platform.environment['COMPANY_USERS_SERVICE_URL']??'http://company-users-service:8083'),token),
      catalog:InternalApi(Uri.parse(Platform.environment['GLOBAL_ARTICLES_SERVICE_URL']??'http://global-articles-service:8082'),token)));

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.handler.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('super-admin-service läuft auf Port ${server.port}');
}
