import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'package:company_users_service/src/repository_memory.dart';
import 'package:company_users_service/src/router.dart';

const _internalToken = 'test-internal-token';

void main() {
  late InMemoryCompanyUserRepository repository;
  late HttpServer server;
  late Uri baseUrl;

  setUp(() async {
    repository = InMemoryCompanyUserRepository();
    final router = CompanyUserRouter(repository: repository, internalToken: _internalToken);
    server = await shelf_io.serve(router.handler.call, 'localhost', 0);
    baseUrl = Uri.parse('http://localhost:${server.port}');
  });

  tearDown(() => server.close(force: true));

  Future<String> createCompany(String name) async {
    final response = await http.post(
      baseUrl.resolve('/internal/companies'),
      headers: {'x-internal-token': _internalToken},
      body: jsonEncode({'name': name}),
    );
    expect(response.statusCode, 201);
    return (jsonDecode(response.body) as Map<String, Object?>)['companyId'] as String;
  }

  Future<({String userId, String activationToken})> createAdmin(String companyId, String username) async {
    final response = await http.post(
      baseUrl.resolve('/internal/companies/$companyId/admins'),
      headers: {'x-internal-token': _internalToken},
      body: jsonEncode({'username': username}),
    );
    expect(response.statusCode, 201);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return (userId: body['userId'] as String, activationToken: body['activationToken'] as String);
  }

  Future<void> activate(String token, String password) async {
    final response = await http.post(
      baseUrl.resolve('/auth/activate'),
      body: jsonEncode({'token': token, 'password': password}),
    );
    expect(response.statusCode, 200);
  }

  Future<String> login(String username, String password) async {
    final response = await http.post(
      baseUrl.resolve('/auth/login'),
      body: jsonEncode({'username': username, 'password': password}),
    );
    expect(response.statusCode, 200);
    return (jsonDecode(response.body) as Map<String, Object?>)['token'] as String;
  }

  test('/internal/companies ohne gültigen X-Internal-Token liefert 403', () async {
    final response = await http.post(
      baseUrl.resolve('/internal/companies'),
      headers: {'x-internal-token': 'falsch'},
      body: jsonEncode({'name': 'Firma X'}),
    );
    expect(response.statusCode, 403);
  });

  test(
    'Voller M1-Ablauf: Admin meldet sich nach Aktivierung an, legt einen Zeichner an, '
    'der sich ebenfalls anmelden kann',
    () async {
      final companyId = await createCompany('Firma A');
      final adminProvision = await createAdmin(companyId, 'admin-a');
      await activate(adminProvision.activationToken, 'admin-passwort-1');
      final adminToken = await login('admin-a', 'admin-passwort-1');

      final meResponse = await http.get(
        baseUrl.resolve('/me'),
        headers: {'authorization': 'Bearer $adminToken'},
      );
      expect(meResponse.statusCode, 200);
      final me = jsonDecode(meResponse.body) as Map<String, Object?>;
      expect(me['role'], 'admin');
      expect(me['companyName'], 'Firma A');

      final createZeichnerResponse = await http.post(
        baseUrl.resolve('/users'),
        headers: {'authorization': 'Bearer $adminToken'},
        body: jsonEncode({'username': 'zeichner-a'}),
      );
      expect(createZeichnerResponse.statusCode, 201);
      final zeichnerActivationToken =
          (jsonDecode(createZeichnerResponse.body) as Map<String, Object?>)['activationToken'] as String;

      await activate(zeichnerActivationToken, 'zeichner-passwort-1');
      final zeichnerToken = await login('zeichner-a', 'zeichner-passwort-1');
      final zeichnerMe = await http.get(
        baseUrl.resolve('/me'),
        headers: {'authorization': 'Bearer $zeichnerToken'},
      );
      expect((jsonDecode(zeichnerMe.body) as Map<String, Object?>)['role'], 'zeichner');
    },
  );

  test(
    'Admin A kann keine Nutzer in Firma B sehen/ändern, auch nicht über direkte API-Aufrufe',
    () async {
      final companyAId = await createCompany('Firma A');
      final companyBId = await createCompany('Firma B');
      final adminA = await createAdmin(companyAId, 'admin-a');
      await activate(adminA.activationToken, 'admin-passwort-1');
      final adminAToken = await login('admin-a', 'admin-passwort-1');

      final adminB = await createAdmin(companyBId, 'admin-b');
      await activate(adminB.activationToken, 'admin-passwort-2');

      // Admin A sieht in /users nur Firma A, nicht admin-b.
      final listResponse = await http.get(
        baseUrl.resolve('/users'),
        headers: {'authorization': 'Bearer $adminAToken'},
      );
      final users = (jsonDecode(listResponse.body) as Map<String, Object?>)['users'] as List;
      expect(users.map((u) => (u as Map<String, Object?>)['username']), ['admin-a']);

      // Direkter API-Aufruf: Admin A versucht, admin-b (Firma B) zu
      // deaktivieren — muss scheitern, nicht nur in der Liste fehlen.
      final patchResponse = await http.patch(
        baseUrl.resolve('/users/${adminB.userId}'),
        headers: {'authorization': 'Bearer $adminAToken'},
        body: jsonEncode({'active': false}),
      );
      expect(patchResponse.statusCode, 404);
    },
  );

  test('Zeichner erreicht keine Benutzerverwaltung, auch nicht über direkte API-Aufrufe', () async {
    final companyId = await createCompany('Firma A');
    final admin = await createAdmin(companyId, 'admin-a');
    await activate(admin.activationToken, 'admin-passwort-1');
    final adminToken = await login('admin-a', 'admin-passwort-1');

    final zeichnerResponse = await http.post(
      baseUrl.resolve('/users'),
      headers: {'authorization': 'Bearer $adminToken'},
      body: jsonEncode({'username': 'zeichner-a'}),
    );
    final zeichnerActivationToken =
        (jsonDecode(zeichnerResponse.body) as Map<String, Object?>)['activationToken'] as String;
    await activate(zeichnerActivationToken, 'zeichner-passwort-1');
    final zeichnerToken = await login('zeichner-a', 'zeichner-passwort-1');

    final listAsZeichner = await http.get(
      baseUrl.resolve('/users'),
      headers: {'authorization': 'Bearer $zeichnerToken'},
    );
    expect(listAsZeichner.statusCode, 403);

    final createAsZeichner = await http.post(
      baseUrl.resolve('/users'),
      headers: {'authorization': 'Bearer $zeichnerToken'},
      body: jsonEncode({'username': 'noch-ein-zeichner'}),
    );
    expect(createAsZeichner.statusCode, 403);
  });

  test('Gesperrte/deaktivierte Anmeldung schlägt fehl; Testadmin von Firma B bleibt unabhängig', () async {
    final companyAId = await createCompany('Firma A');
    final companyBId = await createCompany('Firma B');
    final adminA = await createAdmin(companyAId, 'admin-a');
    await activate(adminA.activationToken, 'admin-passwort-1');
    final adminAToken = await login('admin-a', 'admin-passwort-1');

    final adminB = await createAdmin(companyBId, 'admin-b');
    await activate(adminB.activationToken, 'admin-passwort-2');
    final adminBTokenBefore = await login('admin-b', 'admin-passwort-2');
    expect(adminBTokenBefore, isNotEmpty);

    // Admin A legt einen Zeichner an und deaktiviert ihn wieder.
    final zeichnerResponse = await http.post(
      baseUrl.resolve('/users'),
      headers: {'authorization': 'Bearer $adminAToken'},
      body: jsonEncode({'username': 'zeichner-a'}),
    );
    final zeichnerBody = jsonDecode(zeichnerResponse.body) as Map<String, Object?>;
    await activate(zeichnerBody['activationToken'] as String, 'zeichner-passwort-1');

    final deactivateResponse = await http.patch(
      baseUrl.resolve('/users/${zeichnerBody['userId']}'),
      headers: {'authorization': 'Bearer $adminAToken'},
      body: jsonEncode({'active': false}),
    );
    expect(deactivateResponse.statusCode, 200);

    final loginAfterDeactivate = await http.post(
      baseUrl.resolve('/auth/login'),
      body: jsonEncode({'username': 'zeichner-a', 'password': 'zeichner-passwort-1'}),
    );
    expect(loginAfterDeactivate.statusCode, 403);

    // Firma B komplett unberührt von alldem.
    final adminBMeResponse = await http.get(
      baseUrl.resolve('/me'),
      headers: {'authorization': 'Bearer $adminBTokenBefore'},
    );
    expect((jsonDecode(adminBMeResponse.body) as Map<String, Object?>)['companyName'], 'Firma B');
  });

  test('Den letzten aktiven Admin einer Firma kann niemand deaktivieren', () async {
    final companyId = await createCompany('Firma A');
    final admin = await createAdmin(companyId, 'admin-a');
    await activate(admin.activationToken, 'admin-passwort-1');
    final adminToken = await login('admin-a', 'admin-passwort-1');

    final response = await http.patch(
      baseUrl.resolve('/users/${admin.userId}'),
      headers: {'authorization': 'Bearer $adminToken'},
      body: jsonEncode({'active': false}),
    );
    expect(response.statusCode, 409);
  });

  test('Ein zweiter aktivierter Admin kann den ersten deaktivieren (nicht mehr "letzter")', () async {
    final companyId = await createCompany('Firma A');
    final admin1 = await createAdmin(companyId, 'admin-1');
    await activate(admin1.activationToken, 'admin-passwort-1');
    final admin1Token = await login('admin-1', 'admin-passwort-1');

    final admin2 = await createAdmin(companyId, 'admin-2');
    await activate(admin2.activationToken, 'admin-passwort-2');

    final response = await http.patch(
      baseUrl.resolve('/users/${admin1.userId}'),
      headers: {'authorization': 'Bearer $admin1Token'},
      body: jsonEncode({'active': false}),
    );
    expect(response.statusCode, 200);
  });

  test('Aktivierungstoken ist nur einmal einlösbar', () async {
    final companyId = await createCompany('Firma A');
    final admin = await createAdmin(companyId, 'admin-a');
    await activate(admin.activationToken, 'erstes-passwort-123');

    final secondAttempt = await http.post(
      baseUrl.resolve('/auth/activate'),
      body: jsonEncode({'token': admin.activationToken, 'password': 'zweites-passwort-456'}),
    );
    expect(secondAttempt.statusCode, 400);
  });

  test('Ein Fehler beim Anlegen (unbekannte companyId) hinterlässt keinen halben Zugang', () async {
    final response = await http.post(
      baseUrl.resolve('/internal/companies/does-not-exist/admins'),
      headers: {'x-internal-token': _internalToken},
      body: jsonEncode({'username': 'ghost-admin'}),
    );
    expect(response.statusCode, 404);
    expect(await repository.findUserByUsername('ghost-admin'), isNull);
  });
}
