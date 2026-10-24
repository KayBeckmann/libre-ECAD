import 'dart:convert';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models.dart';
import '../repository.dart';
import 'store.dart';
import 'article_data.dart';
import 'global_catalog.dart';

class WorkspaceRouter {
  WorkspaceRouter({
    required this.store,
    required this.users,
    required this.authenticate,
    this.globalLookup,
  });
  final WorkspaceStore store;
  final Future<Document?> Function(String)? globalLookup;
  final CompanyUserRepository users;
  final Future<AppUser?> Function(Request) authenticate;

  Router get handler {
    final r = Router();
    r.get('/projects', (Request q) => _guard(q, _listProjects));
    r.post('/projects', (Request q) => _guard(q, _createProject));
    r.get(
      '/projects/<id>',
      (Request q, String id) => _guard(q, (q, u) => _project(q, u, Uri.decodeComponent(id))),
    );
    r.patch(
      '/projects/<id>',
      (Request q, String id) => _guard(q, (q, u) => _project(q, u, Uri.decodeComponent(id))),
    );
    r.post(
      '/global-articles/<id>/copy',
      (Request q, String id) => _guard(q, (q, u) => _importGlobal(q, u, Uri.decodeComponent(id))),
    );
    r.get('/articles', (Request q) => _guard(q, _listArticles));
    r.post('/articles', (Request q) => _guard(q, _createArticle));
    r.get(
      '/articles/<id>',
      (Request q, String id) => _guard(q, (q, u) => _article(q, u, Uri.decodeComponent(id))),
    );
    r.patch(
      '/articles/<id>',
      (Request q, String id) => _guard(q, (q, u) => _article(q, u, Uri.decodeComponent(id))),
    );
    r.get(
      '/articles/<id>/history',
      (Request q, String id) => _guard(q, (q, u) => _articleHistory(q, u, Uri.decodeComponent(id))),
    );
    r.post(
      '/articles/<id>/copy',
      (Request q, String id) => _guard(q, (q, u) => _copyArticle(q, u, Uri.decodeComponent(id))),
    );
    return r;
  }

  Future<Response> _guard(
    Request request,
    Future<Response> Function(Request, AppUser) action,
  ) async {
    final user = await authenticate(request);
    if (user == null)
      return jsonError(
        'Nicht angemeldet oder Zugang deaktiviert.',
        status: 401,
      );
    try {
      return await action(request, user);
    } on GlobalCatalogUnavailable {
      return jsonError(
        'Globaler Artikel-Dienst nicht verfügbar. Lokale Daten bleiben unverändert.',
        status: 503,
      );
    } on FormatException catch (e) {
      return jsonError(e.message);
    }
  }

  Future<Document> _body(Request q) async {
    final bytes = <int>[];
    await for (final part in q.read()) {
      bytes.addAll(part);
      if (bytes.length > 131072)
        throw FormatException('Anfrage zu groß (max. 128 KiB).');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>)
      throw FormatException('JSON-Objekt erwartet.');
    return value;
  }

  String _text(Document d, String key, {int max = 200, bool optional = false}) {
    final value = d[key];
    if (optional && value == null) return '';
    if (value is! String ||
        (!optional && value.trim().isEmpty) ||
        value.length > max) {
      throw FormatException(
        '$key: ${optional ? "Text" : "Pflichtfeld"}, maximal $max Zeichen.',
      );
    }
    return value.trim();
  }

  bool _admin(AppUser u) => u.role == UserRole.admin;
  bool _projectVisible(Document p, AppUser u) =>
      _admin(u) || (p['memberIds'] as List).contains(u.id);
  Future<List<String>> _members(Document d, AppUser u) async {
    final values = d['memberIds'] ?? <String>[];
    if (values is! List ||
        values.length > 500 ||
        values.any((e) => e is! String)) {
      throw FormatException('memberIds muss eine Liste von Nutzer-IDs sein.');
    }
    final members = values.cast<String>().toSet().toList();
    for (final id in members) {
      final member = await users.findUserById(id);
      if (member == null ||
          member.companyId != u.companyId ||
          !member.active ||
          !member.isActivated) {
        throw FormatException(
          'Projektmitglieder müssen aktive Nutzer der eigenen Firma sein.',
        );
      }
    }
    return members;
  }

  Document _newDocument(AppUser u) => {
    'id': SessionTokens.generate(),
    'version': 1,
    'createdBy': u.id,
    'updatedBy': u.id,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Document _revision(Document old, AppUser u) => {
    ...old,
    'version': (old['version'] as int) + 1,
    'updatedBy': u.id,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Response _conflict() => jsonError(
    'Stand wurde geändert. Neu laden, Änderungen vergleichen und bewusst erneut speichern.',
    status: 409,
  );

  Future<Response> _listProjects(Request q, AppUser u) async => jsonOk({
    'projects': (await store.list(
      u.companyId,
      'project',
    )).where((p) => _projectVisible(p, u)).toList(),
  });

  Future<Response> _createProject(Request q, AppUser u) async {
    if (!_admin(u))
      return jsonError('Nur Firmenadmins legen Projekte an.', status: 403);
    final d = await _body(q);
    final p = {
      ..._newDocument(u),
      'name': _text(d, 'name'),
      'description': _text(d, 'description', max: 4000, optional: true),
      'memberIds': await _members(d, u),
    };
    await store.create(u.companyId, 'project', p);
    return jsonOk(p, status: 201);
  }

  Future<Response> _project(Request q, AppUser u, String id) async {
    final p = await store.get(u.companyId, 'project', id);
    if (p == null || !_projectVisible(p, u))
      return jsonError('Projekt nicht gefunden.', status: 404);
    if (q.method == 'GET') return jsonOk(p);
    final d = await _body(q);
    if (d['version'] is! int) throw FormatException('version ist Pflicht.');
    if (d['version'] != p['version']) return _conflict();
    if (!_admin(u) && d.containsKey('memberIds'))
      return jsonError('Nur Firmenadmins verwalten Mitglieder.', status: 403);
    final next = {
      ..._revision(p, u),
      'name': _text(d, 'name'),
      'description': _text(d, 'description', max: 4000, optional: true),
      'memberIds': _admin(u) && d.containsKey('memberIds')
          ? await _members(d, u)
          : p['memberIds'],
    };
    if (!await store.update(u.companyId, 'project', next, d['version'] as int))
      return _conflict();
    return jsonOk(next);
  }

  bool _articleVisible(Document a, AppUser u) =>
      a['scope'] == 'company' || a['ownerId'] == u.id;
  bool _articleWritable(Document a, AppUser u) =>
      a['scope'] == 'personal' ? a['ownerId'] == u.id : _admin(u);
  String _scope(Document d) {
    final scope = d['scope'];
    if (scope != 'personal' && scope != 'company')
      throw FormatException('scope: personal oder company erwartet.');
    return scope as String;
  }

  Document _layerIds(Document layers, {Document? previous}) => {
    for (final name in layers.keys)
      name: {
        ...(layers[name] as Map),
        'id': previous == null
            ? SessionTokens.generate()
            : (previous[name] as Map)['id'],
      },
  };
  Future<Document?> _findArticle(String id, AppUser u) async {
    final a = await store.get(u.companyId, 'article', id);
    return a != null && _articleVisible(a, u) ? a : null;
  }

  Future<Response> _listArticles(Request q, AppUser u) async {
    final scope = q.url.queryParameters['scope'];
    if (scope != null && scope != 'personal' && scope != 'company')
      throw FormatException('Unbekannter Artikelbereich.');
    final query = (q.url.queryParameters['query'] ?? '').trim().toLowerCase();
    final rows = (await store.list(u.companyId, 'article')).where(
      (a) =>
          _articleVisible(a, u) &&
          (scope == null || a['scope'] == scope) &&
          ('${a['articleNumber']} ${a['name']}'.toLowerCase().contains(query)),
    );
    return jsonOk({'articles': rows.map(withArticleWarnings).toList()});
  }

  Future<Response> _createArticle(Request q, AppUser u) async {
    final d = await _body(q);
    final scope = _scope(d);
    if (scope == 'company' && !_admin(u))
      return jsonError('Nur Firmenadmins ändern den Firmenstamm.', status: 403);
    final fields = articleFields(d);
    final a = {
      ..._newDocument(u),
      ...fields,
      'layers': _layerIds(fields['layers'] as Document),
      'scope': scope,
      'ownerId': scope == 'personal' ? u.id : null,
      'source': null,
    };
    await store.create(u.companyId, 'article', a);
    return jsonOk(withArticleWarnings(a), status: 201);
  }

  Future<Response> _article(Request q, AppUser u, String id) async {
    final a = await _findArticle(id, u);
    if (a == null) return jsonError('Artikel nicht gefunden.', status: 404);
    if (q.method == 'GET') return jsonOk(withArticleWarnings(a));
    if (!_articleWritable(a, u))
      return jsonError('Keine Schreibrechte für diesen Artikel.', status: 403);
    final d = await _body(q);
    if (d['version'] is! int) throw FormatException('version ist Pflicht.');
    if (d['version'] != a['version']) return _conflict();
    final fields = articleFields(d);
    final next = {
      ..._revision(a, u),
      ...fields,
      'layers': _layerIds(
        fields['layers'] as Document,
        previous: a['layers'] as Document,
      ),
    };
    if (!await store.update(u.companyId, 'article', next, d['version'] as int))
      return _conflict();
    return jsonOk(withArticleWarnings(next));
  }

  Future<Response> _articleHistory(Request q, AppUser u, String id) async {
    if (await _findArticle(id, u) == null)
      return jsonError('Artikel nicht gefunden.', status: 404);
    return jsonOk({
      'versions': (await store.history(
        u.companyId,
        'article',
        id,
      )).map(withArticleWarnings).toList(),
    });
  }

  Future<Response> _copyArticle(Request q, AppUser u, String id) async {
    final a = await _findArticle(id, u);
    if (a == null) return jsonError('Artikel nicht gefunden.', status: 404);
    final d = await _body(q);
    final scope = _scope(d);
    if (scope == 'company' && !_admin(u))
      return jsonError(
        'Nur Firmenadmins übernehmen in den Firmenstamm.',
        status: 403,
      );
    if (d['version'] != a['version']) return _conflict();
    final copy = {
      ...a,
      ..._newDocument(u),
      'scope': scope,
      'ownerId': scope == 'personal' ? u.id : null,
      'layers': _layerIds(a['layers'] as Document),
      'source': {
        'kind': 'local',
        'articleId': a['id'],
        'version': a['version'],
        'scope': a['scope'],
        'origin': a['origin'],
        'license': a['license'],
        'upstream': a['source'],
      },
    };
    await store.create(u.companyId, 'article', copy);
    return jsonOk(withArticleWarnings(copy), status: 201);
  }

  Future<Response> _importGlobal(Request q, AppUser u, String id) async {
    final d = await _body(q);
    final scope = _scope(d);
    if (scope == 'company' && !_admin(u))
      return jsonError(
        'Nur Firmenadmins übernehmen in den Firmenstamm.',
        status: 403,
      );
    if (globalLookup == null) throw GlobalCatalogUnavailable();
    final source = await globalLookup!(id);
    if (source == null)
      return jsonError('Globaler Artikel nicht gefunden.', status: 404);
    if (d['version'] != source['version']) return _conflict();
    // M1 catalog exposes synthetic metadata, not licensed technical layers.
    // Never infer license or verification from a manufacturer area label.
    final fields = articleFields({
      'articleNumber': source['articleNumber'],
      'name': source['name'],
      'license': source['license'] ?? 'Ungeklärt – synthetische Katalog-Beispieldaten',
      'origin':
          source['origin'] ?? 'Globaler Katalog / ${source['source']} / ${source['manufacturerName'] ?? "Allgemein"}',
      'notes':
          source['attribution'] == null ? 'Synthetische Katalogmetadaten; technische Ebenen fehlen. Keine Herstellerverifikation.' : 'Namensnennung: ${source['attribution']}. Technische Werte ungeprüft.',
      'layers': source['layers'] ?? <String, dynamic>{},
    });
    final a = {
      ..._newDocument(u),
      ...fields,
      'layers': _layerIds(fields['layers'] as Document),
      'scope': scope,
      'ownerId': scope == 'personal' ? u.id : null,
      'source': {
        'kind': 'global',
        'catalog': 'libre-ecad-global',
        'articleId': source['id'],
        'version': source['version'],
        'area': source['source'],
        'manufacturerName': source['manufacturerName'],
        'license': source['license'],
        'attribution': source['attribution'],
        'identityVerification': source['identityVerification'],
      },
    };
    await store.create(u.companyId, 'article', a);
    return jsonOk(withArticleWarnings(a), status: 201);
  }
}
