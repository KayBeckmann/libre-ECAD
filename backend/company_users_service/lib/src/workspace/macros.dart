import 'package:ecad_core/ecad_core.dart' show macroFields;
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models.dart';
import 'store.dart';

class MacroRouter {
  MacroRouter({
    required this.store,
    required this.authenticate,
    this.catalogApi,
  });
  final WorkspaceStore store;
  final InternalApi? catalogApi;
  final Future<AppUser?> Function(Request) authenticate;
  bool visible(Document d, AppUser u) =>
      d['scope'] == 'company' || d['ownerId'] == u.id;
  bool writable(Document d, AppUser u) => d['scope'] == 'personal'
      ? d['ownerId'] == u.id
      : u.role == UserRole.admin;
  Document identity(AppUser u) => {
    'id': SessionTokens.generate(),
    'version': 1,
    'createdBy': u.id,
    'updatedBy': u.id,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Future<Response> guard(
    Request q,
    Future<Response> Function(AppUser) action,
  ) => apiGuard(() async {
    final u = await authenticate(q);
    if (u == null) return jsonError('Nicht angemeldet.', status: 401);
    return action(u);
  });
  Router get handler {
    final r = Router();
    r.get(
      '/',
      (Request q) => guard(q, (u) async {
        final query = (q.url.queryParameters['query'] ?? '').toLowerCase(),
            scope = q.url.queryParameters['scope'];
        if (scope != null && !['personal', 'company'].contains(scope))
          throw ApiProblem(400, 'Unbekannter Makrobereich.');
        return jsonOk({
          'macros': (await store.list(u.companyId, 'macro'))
              .where(
                (d) =>
                    visible(d, u) &&
                    (scope == null || d['scope'] == scope) &&
                    '${d['name']} ${(d['groups'] as List).join(' ')}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList(),
        });
      }),
    );
    r.post(
      '/',
      (Request q) => guard(q, (u) async {
        final b = await readJson(q, maxBytes: 4194304), scope = b['scope'];
        if (!['personal', 'company'].contains(scope))
          throw ApiProblem(400, 'Bereich personal/company erforderlich.');
        if (scope == 'company' && u.role != UserRole.admin)
          throw ApiProblem(403, 'Firmenmakros benötigen Adminrechte.');
        final d = {
          ...identity(u),
          ...macroFields(b),
          'scope': scope,
          'ownerId': scope == 'personal' ? u.id : null,
        };
        await store.create(u.companyId, 'macro', d);
        return jsonOk(d, status: 201);
      }),
    );
    for (final method in ['GET', 'PATCH'])
      r.add(
        method,
        '/<id>',
        (Request q, String id) => guard(q, (u) async {
          final old = await store.get(
            u.companyId,
            'macro',
            Uri.decodeComponent(id),
          );
          if (old == null || !visible(old, u))
            throw ApiProblem(404, 'Makro nicht gefunden.');
          if (q.method == 'GET') return jsonOk(old);
          if (!writable(old, u))
            throw ApiProblem(403, 'Makro nicht bearbeitbar.');
          final b = await readJson(q, maxBytes: 4194304),
              version = expectedVersion(b);
          final next = {
            ...old,
            ...macroFields(b),
            'version': version + 1,
            'updatedBy': u.id,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          };
          if (!await store.update(u.companyId, 'macro', next, version))
            throw ApiProblem(409, 'Makro geändert. Neu laden und vergleichen.');
          return jsonOk(next);
        }),
      );
    r.get(
      '/<id>/history',
      (Request q, String id) => guard(q, (u) async {
        final old = await store.get(
          u.companyId,
          'macro',
          Uri.decodeComponent(id),
        );
        if (old == null || !visible(old, u))
          throw ApiProblem(404, 'Makro nicht gefunden.');
        return jsonOk({
          'versions': await store.history(u.companyId, 'macro', old['id']),
        });
      }),
    );
    r.post(
      '/global/<id>/copy',
      (Request q, String id) => guard(q, (u) async {
        if (catalogApi == null)
          throw ApiProblem(503, 'Globaler Katalog nicht verfügbar.');
        final b = await readJson(q), scope = b['scope'];
        if (!['personal', 'company'].contains(scope))
          throw ApiProblem(400, 'Unbekannter Bereich.');
        if (scope == 'company' && u.role != UserRole.admin)
          throw ApiProblem(403, 'Firmenmakros benötigen Adminrechte.');
        final result = await catalogApi!.call(
          '/internal/contributions',
          method: 'POST',
          body: {
            'action': 'publicMacros',
            'actor': {
              'companyId': u.companyId,
              'userId': u.id,
              'role': u.role.wireValue,
            },
          },
        );
        final a = (result['macros'] as List)
            .cast<Document>()
            .where((m) => m['id'] == Uri.decodeComponent(id))
            .firstOrNull;
        if (a == null) throw ApiProblem(404, 'Globales Makro nicht gefunden.');
        if (expectedVersion(b) != a['version'])
          throw ApiProblem(409, 'Quellversion geändert.');
        final d = {
          ...identity(u),
          ...macroFields(a),
          'scope': scope,
          'ownerId': scope == 'personal' ? u.id : null,
          'source': {
            'kind': 'global',
            'id': a['id'],
            'version': a['version'],
            'origin': a['origin'],
            'license': a['license'],
          },
        };
        await store.create(u.companyId, 'macro', d);
        return jsonOk(d, status: 201);
      }),
    );
    r.post(
      '/<id>/copy',
      (Request q, String id) => guard(q, (u) async {
        final old = await store.get(
          u.companyId,
          'macro',
          Uri.decodeComponent(id),
        );
        if (old == null || !visible(old, u))
          throw ApiProblem(404, 'Makro nicht gefunden.');
        final b = await readJson(q), scope = b['scope'];
        if (!['personal', 'company'].contains(scope))
          throw ApiProblem(400, 'Unbekannter Bereich.');
        if (scope == 'company' && u.role != UserRole.admin)
          throw ApiProblem(403, 'Firmenmakros benötigen Adminrechte.');
        if (expectedVersion(b) != old['version'])
          throw ApiProblem(409, 'Quellversion geändert.');
        final d = {
          ...old,
          ...identity(u),
          'scope': scope,
          'ownerId': scope == 'personal' ? u.id : null,
          'source': {
            'id': old['id'],
            'version': old['version'],
            'origin': old['origin'],
            'license': old['license'],
          },
        };
        await store.create(u.companyId, 'macro', d);
        return jsonOk(d, status: 201);
      }),
    );
    return r;
  }
}
