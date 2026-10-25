import 'package:ecad_core/ecad_core.dart' hide Json, cloneJson;
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models.dart';
import '../repository.dart';
import 'store.dart';

/// Scoped credentials cannot call the session-only review or workspace routes.
/// Proposals are immutable; the project history is authoritative for acceptance.
class AutomationRouter {
  AutomationRouter({
    required this.records,
    required this.store,
    required this.users,
    required this.authenticate,
  });
  final Records records;
  final WorkspaceStore store;
  final CompanyUserRepository users;
  final Future<AppUser?> Function(Request) authenticate;
  static const tokens = 'm6-automation-token',
      proposals = 'm6-drawing-proposal';

  Router get handler {
    final r = Router();
    for (final method in ['GET', 'POST']) {
      r.add(
        method,
        '/tokens',
        (Request q) => _session(q, (u) => _tokens(q, u)),
      );
    }
    r.post(
      '/tokens/<id>/revoke',
      (Request q, String id) => _session(
        q,
        (u) => records.transaction((tx) async {
          final token = await tx.get(tokens, id);
          if (token == null ||
              token['userId'] != u.id ||
              token['companyId'] != u.companyId)
            return jsonError('Zugang nicht gefunden.', status: 404);
          await tx.put(
            tokens,
            {...token, 'revoked': true},
            expected: token['version'],
            actor: u.id,
            reason: 'Nutzer widerruft API-Zugang',
          );
          return jsonOk({'revoked': true});
        }),
      ),
    );
    r.get(
      '/projects',
      (Request q) => _scoped(q, (u, t, tx) async {
        final items = (await store.list(u.companyId, 'project'))
            .where(
              (p) =>
                  _visible(p, u) && (t['projectIds'] as List).contains(p['id']),
            )
            .toList();
        return jsonOk({
          'projects': [
            for (final p in items)
              {'id': p['id'], 'name': p['name'], 'version': p['version']},
          ],
        });
      }),
    );
    r.get(
      '/projects/<id>',
      (Request q, String id) => _scoped(q, (u, t, tx) async {
        final p = await _project(u, id, t);
        return p == null
            ? jsonError('Projekt nicht gefunden.', status: 404)
            : jsonOk(_public(p));
      }),
    );
    r.get(
      '/projects/<id>/documents',
      (Request q, String id) => _scoped(q, (u, t, tx) async {
        final p = await _project(u, id, t);
        if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
        if (int.tryParse(q.url.queryParameters['version'] ?? '') !=
            p['version'])
          return _conflict();
        if (p['drawing'] == null)
          return jsonError('Zuerst eine Zeichnung speichern.');
        return jsonOk({
          'projectId': id,
          'version': p['version'],
          'data': documentData(p),
          'findings': drawingFindings(p['drawing']),
        });
      }),
    );
    r.post(
      '/projects/<id>/proposals',
      (Request q, String id) => _scoped(q, (u, t, tx) async {
        if (t['allowProposals'] != true)
          return jsonError('Zugang erlaubt nur Lesen.', status: 403);
        final p = await _project(u, id, t);
        if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
        final b = await readJson(q, maxBytes: 4194304);
        if (b['version'] != p['version']) return _conflict();
        final reason = b['reason'];
        if (reason is! String || reason.trim().isEmpty || reason.length > 1000)
          throw FormatException('Begründung mit 1–1000 Zeichen erforderlich.');
        final proposal = await tx.put(
          proposals,
          {
            'id': SessionTokens.generate(),
            'companyId': u.companyId,
            'projectId': id,
            'baseVersion': p['version'],
            'drawing': validateDrawing(b['drawing']),
            'tokenId': t['id'],
            'proposedBy': u.id,
          },
          expected: 0,
          actor: u.id,
          reason: reason.trim(),
        );
        return jsonOk({
          'id': proposal['id'],
          'projectId': id,
          'baseVersion': p['version'],
          'status': 'pending-human-review',
        }, status: 201);
      }),
    );
    r.get(
      '/review/<id>',
      (Request q, String id) => _session(q, (u) async {
        final p = await _project(u, id, null);
        if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
        final history = await store.history(u.companyId, 'project', id);
        final accepted = {
          for (final v in history)
            if (v['activity']?['proposalId'] != null)
              v['activity']['proposalId'],
        };
        return records.transaction(
          (tx) async => jsonOk({
            'project': _public(p),
            'proposals': [
              for (final v in await tx.list(proposals))
                if (v['companyId'] == u.companyId && v['projectId'] == id)
                  {
                    ...v,
                    'status': accepted.contains(v['id'])
                        ? 'applied'
                        : v['baseVersion'] == p['version']
                        ? 'pending'
                        : 'stale',
                  },
            ],
          }),
        );
      }),
    );
    r.post(
      '/review/<id>/<proposalId>/apply',
      (Request q, String id, String proposalId) => _session(q, (u) async {
        final b = await readJson(q, maxBytes: 4194304);
        if (b['confirmed'] != true)
          throw FormatException(
            'Vergleich und Übernahme ausdrücklich bestätigen.',
          );
        final p = await _project(u, id, null);
        if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
        final v = await records.transaction(
          (tx) => tx.get(proposals, proposalId),
        );
        if (v == null || v['companyId'] != u.companyId || v['projectId'] != id)
          return jsonError('Vorschlag nicht gefunden.', status: 404);
        if (b['version'] != p['version'] || v['baseVersion'] != p['version'])
          return _conflict();
        final next = {
          for (final e in p.entries)
            if (e.key != 'release') e.key: e.value,
          'drawing': v['drawing'],
          'version': (p['version'] as int) + 1,
          'updatedBy': u.id,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'activity': {
            'action': 'automation-proposal-applied',
            'proposalId': proposalId,
            'proposedBy': v['proposedBy'],
            'tokenId': v['tokenId'],
            'reason': v['reason'],
            'confirmedBy': u.id,
            'baseVersion': p['version'],
          },
        };
        if (!await store.update(u.companyId, 'project', next, p['version']))
          return _conflict();
        return jsonOk(_public(next));
      }),
    );
    return r;
  }

  Future<Response> _session(
    Request q,
    Future<Response> Function(AppUser) action,
  ) => apiGuard(() async {
    final u = await authenticate(q);
    if (u == null)
      return jsonError(
        'Anmeldung in der Oberfläche erforderlich.',
        status: 401,
      );
    return action(u);
  });
  Future<Response> _scoped(
    Request q,
    Future<Response> Function(AppUser, Json, RecordSession) action,
  ) => apiGuard(
    () => records.transaction((tx) async {
      final header = q.headers['authorization'] ?? '';
      final raw = header.startsWith('Bearer ') ? header.substring(7) : '';
      final t = raw.isEmpty
          ? null
          : await tx.get(tokens, SessionTokens.hashOf(raw));
      if (t == null ||
          t['revoked'] == true ||
          !DateTime.now().toUtc().isBefore(DateTime.parse(t['expiresAt'])))
        return jsonError(
          'API-Zugang abgelaufen oder widerrufen. In der Oberfläche erneuern.',
          status: 401,
        );
      final u = await users.findUserById(t['userId']);
      final c = await users.findCompanyById(t['companyId']);
      if (u == null ||
          c == null ||
          !u.active ||
          !u.isActivated ||
          !c.active ||
          u.companyId != c.id ||
          u.authEpoch != t['userEpoch'] ||
          c.authEpoch != t['companyEpoch'])
        return jsonError('Zugang gesperrt.', status: 401);
      return action(u, t, tx);
    }),
  );
  bool _visible(Json p, AppUser u) =>
      u.role == UserRole.admin || (p['memberIds'] as List).contains(u.id);
  Future<Json?> _project(AppUser u, String id, Json? token) async {
    if (token != null && !(token['projectIds'] as List).contains(id))
      return null;
    final p = await store.get(u.companyId, 'project', id);
    return p != null && _visible(p, u) ? p : null;
  }

  Json _public(Json p) => {
    for (final key in [
      'id',
      'name',
      'description',
      'version',
      'metadata',
      'drawing',
    ])
      key: p[key],
  };
  Response _conflict() => jsonError(
    'Projektstand geändert. Neu lesen und neuen Vorschlag erstellen; keine automatische Konfliktauflösung.',
    status: 409,
  );
  Future<Response> _tokens(Request q, AppUser u) async {
    if (q.method == 'GET')
      return records.transaction(
        (tx) async => jsonOk({
          'tokens': [
            for (final t in await tx.list(tokens))
              if (t['userId'] == u.id && t['companyId'] == u.companyId) t,
          ],
        }),
      );
    final b = await readJson(q, maxBytes: 4194304);
    if (b['confirmed'] != true)
      throw FormatException('Datenweitergabe bewusst bestätigen.');
    final ids = b['projectIds'];
    if (ids is! List ||
        ids.isEmpty ||
        ids.length > 50 ||
        ids.any((id) => id is! String))
      throw FormatException('1–50 Projekt-IDs erforderlich.');
    for (final id in ids) {
      if (await _project(u, id, null) == null)
        return jsonError('Projekt nicht gefunden.', status: 404);
    }
    final label = b['label'];
    if (label is! String || label.trim().isEmpty || label.length > 100)
      throw FormatException('Bezeichnung mit 1–100 Zeichen erforderlich.');
    final c = (await users.findCompanyById(u.companyId))!;
    final raw = SessionTokens.generate();
    return records.transaction((tx) async {
      final t = await tx.put(
        tokens,
        {
          'id': SessionTokens.hashOf(raw),
          'userId': u.id,
          'companyId': u.companyId,
          'userEpoch': u.authEpoch,
          'companyEpoch': c.authEpoch,
          'label': label.trim(),
          'projectIds': ids.toSet().toList(),
          'allowProposals': b['allowProposals'] == true,
          'revoked': false,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 8))
              .toIso8601String(),
        },
        expected: 0,
        actor: u.id,
        reason: 'Nutzer bestätigt projektbezogene API-Datenweitergabe',
      );
      return jsonOk({...t, 'token': raw}, status: 201);
    });
  }
}
