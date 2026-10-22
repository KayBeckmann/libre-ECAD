import 'dart:convert';
import 'dart:io';

import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'package:super_admin_service/src/company_provisioning_client.dart';
import 'package:super_admin_service/src/repository_memory.dart';
import 'package:super_admin_service/src/router.dart';

/// Fake statt eines echten HTTP-Aufrufs an den Firmen-/Nutzerdienst —
/// der Router wird isoliert getestet (siehe `docs/architecture.md#testing`).
class FakeCompanyProvisioningClient implements CompanyProvisioningClient {
  final List<String> createdCompanies = [];
  bool shouldFail = false;

  @override
  Future<ProvisionedCompany> createCompany({required String name}) async {
    if (shouldFail) throw CompanyProvisioningException('simuliert nicht erreichbar');
    createdCompanies.add(name);
    return ProvisionedCompany(companyId: 'company-${createdCompanies.length}', name: name);
  }

  @override
  Future<ProvisionedAdmin> createFirstAdmin({required String companyId, required String username}) async {
    if (shouldFail) throw CompanyProvisioningException('simuliert nicht erreichbar');
    return ProvisionedAdmin(userId: 'user-1', username: username, activationToken: 'activation-token-xyz');
  }
}

void main() {
  late InMemorySuperAdminRepository repository;
  late FakeCompanyProvisioningClient companyClient;
  late HttpServer server;
  late Uri baseUrl;

  setUp(() async {
    repository = InMemorySuperAdminRepository();
    await repository.createSuperAdmin(
      username: 'kay',
      passwordHash: Passwords.hash('geheim123'),
    );
    companyClient = FakeCompanyProvisioningClient();
    final router = SuperAdminRouter(repository: repository, companyClient: companyClient);
    server = await shelf_io.serve(router.handler.call, 'localhost', 0);
    baseUrl = Uri.parse('http://localhost:${server.port}');
  });

  tearDown(() => server.close(force: true));

  Future<String> login() async {
    final response = await http.post(
      baseUrl.resolve('/auth/login'),
      body: jsonEncode({'username': 'kay', 'password': 'geheim123'}),
    );
    expect(response.statusCode, 200);
    return (jsonDecode(response.body) as Map<String, Object?>)['token'] as String;
  }

  test('GET /health ist ohne Anmeldung erreichbar', () async {
    final response = await http.get(baseUrl.resolve('/health'));
    expect(response.statusCode, 200);
  });

  test('Login mit falschem Passwort liefert 401, kein Token', () async {
    final response = await http.post(
      baseUrl.resolve('/auth/login'),
      body: jsonEncode({'username': 'kay', 'password': 'falsch'}),
    );
    expect(response.statusCode, 401);
  });

  test('Ohne Token liefert jeder geschützte Endpunkt 401 statt Daten', () async {
    final meResponse = await http.get(baseUrl.resolve('/me'));
    expect(meResponse.statusCode, 401);

    final createCompanyResponse = await http.post(
      baseUrl.resolve('/companies'),
      body: jsonEncode({'name': 'Testfirma'}),
    );
    expect(createCompanyResponse.statusCode, 401, reason: 'kein Super-Admin-Endpunkt ohne Anmeldung');
  });

  test('Nach erfolgreichem Login liefert /me den angemeldeten Super-Admin', () async {
    final token = await login();
    final response = await http.get(
      baseUrl.resolve('/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(response.statusCode, 200);
    expect((jsonDecode(response.body) as Map<String, Object?>)['username'], 'kay');
  });

  test(
    'Kay legt zwei Testfirmen und deren initiale Admins an — jede Aktion wird protokolliert',
    () async {
      final token = await login();
      final headers = {'authorization': 'Bearer $token'};

      final companyAResponse = await http.post(
        baseUrl.resolve('/companies'),
        headers: headers,
        body: jsonEncode({'name': 'Firma A'}),
      );
      expect(companyAResponse.statusCode, 201);
      final companyAId =
          (jsonDecode(companyAResponse.body) as Map<String, Object?>)['companyId'] as String;

      final companyBResponse = await http.post(
        baseUrl.resolve('/companies'),
        headers: headers,
        body: jsonEncode({'name': 'Firma B'}),
      );
      expect(companyBResponse.statusCode, 201);

      final adminAResponse = await http.post(
        baseUrl.resolve('/companies/$companyAId/admins'),
        headers: headers,
        body: jsonEncode({'username': 'admin-a'}),
      );
      expect(adminAResponse.statusCode, 201);
      final adminABody = jsonDecode(adminAResponse.body) as Map<String, Object?>;
      expect(adminABody['activationToken'], isNotEmpty);

      expect(companyClient.createdCompanies, ['Firma A', 'Firma B']);

      final auditResponse = await http.get(baseUrl.resolve('/audit'), headers: headers);
      expect(auditResponse.statusCode, 200);
      final entries = (jsonDecode(auditResponse.body) as Map<String, Object?>)['entries'] as List;
      expect(entries, hasLength(3), reason: '2x company.create + 1x company.createAdmin');
    },
  );

  test(
    'Ein Fehler beim Anlegen (Firmen-/Nutzerdienst lehnt ab) hinterlässt keinen Audit-Eintrag — '
    'kein "halber aktiver Zugang"',
    () async {
      final token = await login();
      companyClient.shouldFail = true;

      final response = await http.post(
        baseUrl.resolve('/companies'),
        headers: {'authorization': 'Bearer $token'},
        body: jsonEncode({'name': 'Firma C'}),
      );
      expect(response.statusCode, 502);

      final auditResponse = await http.get(
        baseUrl.resolve('/audit'),
        headers: {'authorization': 'Bearer $token'},
      );
      final entries = (jsonDecode(auditResponse.body) as Map<String, Object?>)['entries'] as List;
      expect(entries, isEmpty);
    },
  );

  test('Logout macht das Token sofort ungültig', () async {
    final token = await login();
    final logoutResponse = await http.post(
      baseUrl.resolve('/auth/logout'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(logoutResponse.statusCode, 204);

    final meResponse = await http.get(
      baseUrl.resolve('/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(meResponse.statusCode, 401);
  });
}
