import 'dart:convert';

import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'company_provisioning_client.dart';
import 'models.dart';
import 'repository.dart';

/// M1.1 Super-Admin-Backend — siehe Roadmap-Abnahme: "Kay legt zwei
/// Testfirmen und deren initiale Admins an"; "ein normaler
/// Firmenadmin kann keinen Super-Admin-Endpunkt ausführen"; "ein
/// Fehler beim Anlegen hinterlässt keinen halben aktiven Zugang."
class SuperAdminRouter {
  SuperAdminRouter({
    required this.repository,
    required this.companyClient,
    this.sessionTtl = const Duration(hours: 8),
  });

  final SuperAdminRepository repository;
  final CompanyProvisioningClient companyClient;
  final Duration sessionTtl;

  Router get handler {
    final router = Router();
    router.get('/health', (Request request) => healthResponse());
    router.post('/auth/login', _login);
    router.post('/auth/logout', _logout);
    router.get('/me', _me);
    router.post('/companies', _createCompany);
    router.post('/companies/<companyId>/admins', _createAdmin);
    router.get('/audit', _listAudit);
    return router;
  }

  Future<Map<String, Object?>> _bodyJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return const {};
    return jsonDecode(raw) as Map<String, Object?>;
  }

  Future<Response> _login(Request request) async {
    final body = await _bodyJson(request);
    final username = body['username'] as String?;
    final password = body['password'] as String?;
    if (username == null || password == null) {
      return jsonError('username und password sind Pflicht.');
    }

    final admin = await repository.findByUsername(username);
    if (admin == null || !Passwords.verify(password, admin.passwordHash)) {
      // Bewusst dieselbe Fehlermeldung für "unbekannter Nutzer" und
      // "falsches Passwort" — keine Enumeration gültiger Logins.
      return jsonError('Benutzername oder Passwort falsch.', status: 401);
    }

    final rawToken = SessionTokens.generate();
    final now = DateTime.now().toUtc();
    await repository.saveSession(
      SuperAdminSession(
        tokenHash: SessionTokens.hashOf(rawToken),
        superAdminId: admin.id,
        createdAt: now,
        expiresAt: now.add(sessionTtl),
      ),
    );
    return jsonOk({'token': rawToken, 'username': admin.username});
  }

  Future<Response> _logout(Request request) async {
    final token = _bearerToken(request);
    if (token != null) {
      await repository.deleteSession(SessionTokens.hashOf(token));
    }
    return Response(204);
  }

  Future<Response> _me(Request request) async {
    final admin = await _requireSuperAdmin(request);
    if (admin == null) return jsonError('Nicht angemeldet.', status: 401);
    return jsonOk({'username': admin.username});
  }

  Future<Response> _createCompany(Request request) async {
    final admin = await _requireSuperAdmin(request);
    if (admin == null) return jsonError('Nicht angemeldet.', status: 401);

    final body = await _bodyJson(request);
    final name = (body['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      return jsonError('name ist Pflicht.');
    }

    try {
      final company = await companyClient.createCompany(name: name);
      await repository.appendAudit(
        AuditEntry(
          id: SessionTokens.generate(),
          superAdminUsername: admin.username,
          action: 'company.create',
          target: '${company.companyId} (${company.name})',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return jsonOk({'companyId': company.companyId, 'name': company.name}, status: 201);
    } on CompanyProvisioningException catch (e) {
      // Kein halber aktiver Zugang: wenn der Firmen-/Nutzerdienst die
      // Anlage ablehnt, wird hier nichts als Audit-Erfolg vermerkt.
      return jsonError(e.message, status: 502);
    }
  }

  Future<Response> _createAdmin(Request request, String companyId) async {
    final admin = await _requireSuperAdmin(request);
    if (admin == null) return jsonError('Nicht angemeldet.', status: 401);

    final body = await _bodyJson(request);
    final username = (body['username'] as String?)?.trim();
    if (username == null || username.isEmpty) {
      return jsonError('username ist Pflicht.');
    }

    try {
      final created = await companyClient.createFirstAdmin(companyId: companyId, username: username);
      await repository.appendAudit(
        AuditEntry(
          id: SessionTokens.generate(),
          superAdminUsername: admin.username,
          action: 'company.createAdmin',
          target: '$companyId -> ${created.username}',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return jsonOk({
        'userId': created.userId,
        'username': created.username,
        'activationToken': created.activationToken,
      }, status: 201);
    } on CompanyProvisioningException catch (e) {
      return jsonError(e.message, status: 502);
    }
  }

  Future<Response> _listAudit(Request request) async {
    final admin = await _requireSuperAdmin(request);
    if (admin == null) return jsonError('Nicht angemeldet.', status: 401);
    final entries = await repository.listAudit();
    return jsonOk({'entries': entries.map((e) => e.toJson()).toList()});
  }

  String? _bearerToken(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  Future<SuperAdmin?> _requireSuperAdmin(Request request) async {
    final token = _bearerToken(request);
    if (token == null) return null;
    final session = await repository.findSession(SessionTokens.hashOf(token));
    if (session == null) return null;
    if (session.isExpired(DateTime.now().toUtc())) {
      await repository.deleteSession(session.tokenHash);
      return null;
    }
    return repository.findById(session.superAdminId);
  }
}
