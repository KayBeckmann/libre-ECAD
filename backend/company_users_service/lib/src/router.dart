import 'workspace/macros.dart';
import 'dart:convert';

import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'models.dart';
import 'repository.dart';
import 'workspace/router.dart';
import 'workspace/automation.dart';
import 'workspace/store.dart';

/// M1.3 Firmen-/Nutzerdienst. Siehe Roadmap-Abnahme: "Admin A erstellt/
/// deaktiviert Zeichner in Firma A, kann keine Nutzer in Firma B
/// sehen/ändern"; "Zeichner erreicht keine Benutzerverwaltung, auch
/// nicht über direkte API-Aufrufe"; "nicht versehentlich letzten
/// Admin aussperren".
class CompanyUserRouter {
  CompanyUserRouter({
    required this.repository,
    required this.internalToken,
    this.workspace,
    this.automationRecords,
    this.catalogApi,
    this.operatorHandler,
    this.globalLookup,
    this.sessionTtl = const Duration(hours: 8),
  });

  final CompanyUserRepository repository;
  final WorkspaceStore? workspace;
  final Records? automationRecords;
  final InternalApi? catalogApi;
  final Handler? operatorHandler;
  final Future<Document?> Function(String)? globalLookup;

  /// Shared Secret für `/internal/*` — siehe `docs/architecture.md`.
  final String internalToken;
  final Duration sessionTtl;

  Router get handler {
    final router = Router();
    router.get('/health', (Request request) => healthResponse());

    // Öffentlich (bzw. mit Nutzer-Session):
    router.post('/auth/activate', _activate);
    router.post('/auth/login', _login);
    router.post('/auth/logout', _logout);
    router.get('/me', _me);
    router.post('/me/password', _changePassword);
    router.get('/users', _listUsers);
    router.post('/users', _createZeichner);
    router.patch('/users/<id>', _setUserActive);

    // Nur für den Super-Admin-Dienst, per Shared Secret geschützt —
    // bewusst kein öffentlich beworbener Pfad.
    router.post('/internal/companies', _internalCreateCompany);
    router.post('/internal/companies/<companyId>/admins', _internalCreateAdmin);

    if (operatorHandler != null)
      router.mount('/internal/operator/', operatorHandler!);
    router.post(
      '/api/v1/contributions',
      (Request request) => apiGuard(() async {
        final auth = await _requireUser(request);
        if (auth == null)
          return jsonError(
            'Nicht angemeldet oder Firmenzugang gesperrt.',
            status: 401,
          );
        if (catalogApi == null)
          return jsonError('Katalog nicht verfügbar.', status: 503);
        final body = await readJson(request, maxBytes: 4194304);
        // All identity and privilege fields come from the local session.
        body.remove('mode');
        body['actor'] = {
          'companyId': auth.user.companyId,
          'userId': auth.user.id,
          'role': auth.user.role.wireValue,
        };
        return jsonOk(
          await catalogApi!.call(
            '/internal/contributions',
            method: 'POST',
            body: body,
          ),
        );
      }),
    );
    if (workspace != null && automationRecords != null) {
      router.mount(
        '/api/v1/automation/',
        AutomationRouter(
          records: automationRecords!,
          store: workspace!,
          users: repository,
          authenticate: (q) async => (await _requireUser(q))?.user,
        ).handler.call,
      );
    }
    if (workspace != null) {
      router.mount(
        '/api/v1/macros/',
        MacroRouter(
          catalogApi: catalogApi,
          store: workspace!,
          authenticate: (q) async => (await _requireUser(q))?.user,
        ).handler.call,
      );
      router.mount(
        '/api/v1/',
        WorkspaceRouter(
          store: workspace!,
          users: repository,
          globalLookup: globalLookup,
          authenticate: (request) async => (await _requireUser(request))?.user,
        ).handler.call,
      );
    }
    return router;
  }

  Future<Map<String, Object?>> _bodyJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return const {};
    return jsonDecode(raw) as Map<String, Object?>;
  }

  // ---- Internal (Super-Admin-Dienst) ----------------------------------

  bool _hasValidInternalToken(Request request) =>
      request.headers['x-internal-token'] == internalToken &&
      internalToken.isNotEmpty;

  Future<Response> _internalCreateCompany(Request request) async {
    if (!_hasValidInternalToken(request))
      return jsonError('Nicht berechtigt.', status: 403);
    final body = await _bodyJson(request);
    final name = (body['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return jsonError('name ist Pflicht.');

    final id = 'company-${DateTime.now().microsecondsSinceEpoch}';
    final company = await repository.createCompany(id: id, name: name);
    return jsonOk({'companyId': company.id, 'name': company.name}, status: 201);
  }

  Future<Response> _internalCreateAdmin(
    Request request,
    String companyId,
  ) async {
    if (!_hasValidInternalToken(request))
      return jsonError('Nicht berechtigt.', status: 403);
    final company = await repository.findCompanyById(companyId);
    if (company == null)
      return jsonError('Firma $companyId existiert nicht.', status: 404);

    final body = await _bodyJson(request);
    final username = (body['username'] as String?)?.trim();
    if (username == null || username.isEmpty)
      return jsonError('username ist Pflicht.');
    if (await repository.findUserByUsername(username) != null) {
      return jsonError(
        'Benutzername "$username" ist bereits vergeben.',
        status: 409,
      );
    }

    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    final created = await repository.createUser(
      id: id,
      companyId: companyId,
      username: username,
      role: UserRole.admin,
    );
    return jsonOk({
      'userId': created.user.id,
      'username': created.user.username,
      'activationToken': created.rawActivationToken,
    }, status: 201);
  }

  // ---- Öffentlich -------------------------------------------------------

  Future<Response> _activate(Request request) async {
    final body = await _bodyJson(request);
    final token = body['token'] as String?;
    final password = body['password'] as String?;
    if (token == null || password == null || password.length < 8) {
      return jsonError('token und password (mind. 8 Zeichen) sind Pflicht.');
    }
    final ok = await repository.activateWithToken(
      rawToken: token,
      passwordHash: Passwords.hash(password),
    );
    if (!ok)
      return jsonError(
        'Aktivierungstoken ungültig, abgelaufen oder bereits benutzt.',
        status: 400,
      );
    return jsonOk({'status': 'activated'});
  }

  Future<Response> _login(Request request) async {
    final body = await _bodyJson(request);
    final username = body['username'] as String?;
    final password = body['password'] as String?;
    if (username == null || password == null)
      return jsonError('username und password sind Pflicht.');

    final user = await repository.findUserByUsername(username);
    if (user == null ||
        !user.isActivated ||
        !Passwords.verify(password, user.passwordHash!)) {
      return jsonError('Benutzername oder Passwort falsch.', status: 401);
    }
    if (!user.active) {
      return jsonError('Dieser Zugang ist deaktiviert.', status: 403);
    }
    final company = await repository.findCompanyById(user.companyId);
    if (company == null || !company.active) {
      return jsonError(
        'Dieses Firmen-Backend ist aktuell gesperrt.',
        status: 403,
      );
    }

    final rawToken = SessionTokens.generate();
    final now = DateTime.now().toUtc();
    await repository.saveSession(
      UserSession(
        tokenHash: SessionTokens.hashOf(rawToken),
        userId: user.id,
        companyId: user.companyId,
        createdAt: now,
        expiresAt: now.add(sessionTtl),
        companyEpoch: company.authEpoch,
        userEpoch: user.authEpoch,
      ),
    );
    return jsonOk({
      'token': rawToken,
      'username': user.username,
      'role': user.role.wireValue,
      'companyName': company.name,
    });
  }

  Future<Response> _logout(Request request) async {
    final token = _bearerToken(request);
    if (token != null)
      await repository.deleteSession(SessionTokens.hashOf(token));
    return Response(204);
  }

  Future<Response> _me(Request request) async {
    final auth = await _requireUser(request);
    if (auth == null) return jsonError('Nicht angemeldet.', status: 401);
    final company = await repository.findCompanyById(auth.user.companyId);
    return jsonOk({
      'username': auth.user.username,
      'role': auth.user.role.wireValue,
      'companyName': company?.name,
    });
  }

  Future<Response> _changePassword(Request request) async {
    final auth = await _requireUser(request);
    if (auth == null) return jsonError('Nicht angemeldet.', status: 401);
    Map<String, Object?> body;
    try {
      body = await readJson(request, maxBytes: 4096);
    } catch (_) {
      return jsonError('Ungültige Anfrage.');
    }
    final current = body['currentPassword'];
    final next = body['newPassword'];
    final confirm = body['confirmPassword'];
    if (current is! String ||
        current.isEmpty ||
        next is! String ||
        next.length < 8 ||
        next.length > 1024 ||
        confirm is! String ||
        confirm != next ||
        next == current) {
      return jsonError(
        'Passwörter prüfen: aktuelles Passwort, neues Passwort (8–1024 Zeichen) und gleiche Bestätigung erforderlich.',
      );
    }
    final changed = await repository.changeOwnPassword(
      userId: auth.user.id,
      currentPassword: current,
      newPasswordHash: Passwords.hash(next),
    );
    if (!changed) return jsonError('Aktuelles Passwort falsch.', status: 403);
    return jsonOk({'status': 'password_changed', 'sessionsRevoked': true});
  }

  Future<Response> _listUsers(Request request) async {
    final auth = await _requireAdmin(request);
    if (auth == null)
      return jsonError(
        'Nicht angemeldet oder keine Admin-Rechte.',
        status: 403,
      );
    final users = await repository.listUsersForCompany(auth.user.companyId);
    return jsonOk({
      'users': [
        for (final u in users)
          {
            'id': u.id,
            'username': u.username,
            'role': u.role.wireValue,
            'active': u.active,
            'activated': u.isActivated,
          },
      ],
    });
  }

  Future<Response> _createZeichner(Request request) async {
    final auth = await _requireAdmin(request);
    if (auth == null)
      return jsonError(
        'Nicht angemeldet oder keine Admin-Rechte.',
        status: 403,
      );

    final body = await _bodyJson(request);
    final username = (body['username'] as String?)?.trim();
    if (username == null || username.isEmpty)
      return jsonError('username ist Pflicht.');
    if (await repository.findUserByUsername(username) != null) {
      return jsonError(
        'Benutzername "$username" ist bereits vergeben.',
        status: 409,
      );
    }

    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    final created = await repository.createUser(
      id: id,
      companyId: auth.user.companyId,
      username: username,
      role: UserRole.zeichner,
    );
    return jsonOk({
      'userId': created.user.id,
      'username': created.user.username,
      'activationToken': created.rawActivationToken,
    }, status: 201);
  }

  Future<Response> _setUserActive(Request request, String id) async {
    final auth = await _requireAdmin(request);
    if (auth == null)
      return jsonError(
        'Nicht angemeldet oder keine Admin-Rechte.',
        status: 403,
      );

    final target = await repository.findUserById(id);
    if (target == null || target.companyId != auth.user.companyId) {
      // Dieselbe Antwort für "existiert nicht" und "gehört zu
      // fremder Firma" — kein Oracle für fremde User-IDs.
      return jsonError('Nutzer nicht gefunden.', status: 404);
    }

    final body = await _bodyJson(request);
    final active = body['active'] as bool?;
    if (active == null) return jsonError('active (bool) ist Pflicht.');

    if (!active && target.role == UserRole.admin) {
      final activeAdmins = await repository.countActiveActivatedAdmins(
        auth.user.companyId,
      );
      final wouldBeLastAdmin =
          activeAdmins <= 1 && target.active && target.isActivated;
      if (wouldBeLastAdmin) {
        return jsonError(
          'Letzten aktiven Admin der Firma kann niemand deaktivieren.',
          status: 409,
        );
      }
    }

    if (!await repository.setUserActive(id: id, active: active))
      return jsonError(
        'Zugang wurde zwischenzeitlich geändert oder ist letzter Admin.',
        status: 409,
      );
    return jsonOk({'id': id, 'active': active});
  }

  // ---- Auth-Helfer --------------------------------------------------------

  String? _bearerToken(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  Future<({AppUser user, UserSession session})?> _requireUser(
    Request request,
  ) async {
    final token = _bearerToken(request);
    if (token == null) return null;
    final session = await repository.findSession(SessionTokens.hashOf(token));
    if (session == null) return null;
    if (session.isExpired(DateTime.now().toUtc())) {
      await repository.deleteSession(session.tokenHash);
      return null;
    }
    final user = await repository.findUserById(session.userId);
    if (user == null ||
        !user.active ||
        user.companyId != session.companyId ||
        user.authEpoch != session.userEpoch)
      return null;
    final company = await repository.findCompanyById(user.companyId);
    if (company == null ||
        !company.active ||
        company.authEpoch != session.companyEpoch)
      return null;
    return (user: user, session: session);
  }

  Future<({AppUser user, UserSession session})?> _requireAdmin(
    Request request,
  ) async {
    final auth = await _requireUser(request);
    if (auth == null || auth.user.role != UserRole.admin) return null;
    return auth;
  }
}
