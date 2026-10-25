import 'dart:convert';
import 'dart:io';
import 'pdf_output.dart';
import 'git_archive.dart';
import 'package:ecad_core/ecad_core.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models.dart';
import '../repository.dart';
import 'store.dart';
import 'project_access.dart';
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
    r.get('/project-groups', (Request q) => _guard(q, _listGroups));
    r.post(
      '/project-groups',
      (Request q) => _guard(q, (q, u) => _saveGroup(q, u)),
    );
    r.patch(
      '/project-groups/<id>',
      (Request q, String id) => _guard(q, (q, u) => _saveGroup(q, u, id)),
    );

    r.get('/projects', (Request q) => _guard(q, _listProjects));
    r.post('/projects', (Request q) => _guard(q, _createProject));
    r.get(
      '/projects/<id>',
      (Request q, String id) =>
          _guard(q, (q, u) => _project(q, u, Uri.decodeComponent(id))),
    );
    r.patch(
      '/projects/<id>',
      (Request q, String id) =>
          _guard(q, (q, u) => _project(q, u, Uri.decodeComponent(id))),
    );
    r.post(
      '/global-articles/<id>/copy',
      (Request q, String id) =>
          _guard(q, (q, u) => _importGlobal(q, u, Uri.decodeComponent(id))),
    );
    r.get('/articles', (Request q) => _guard(q, _listArticles));
    r.post('/articles', (Request q) => _guard(q, _createArticle));
    r.get(
      '/articles/<id>',
      (Request q, String id) =>
          _guard(q, (q, u) => _article(q, u, Uri.decodeComponent(id))),
    );
    r.patch(
      '/articles/<id>',
      (Request q, String id) =>
          _guard(q, (q, u) => _article(q, u, Uri.decodeComponent(id))),
    );
    r.get(
      '/articles/<id>/history',
      (Request q, String id) =>
          _guard(q, (q, u) => _articleHistory(q, u, Uri.decodeComponent(id))),
    );
    r.post(
      '/articles/<id>/copy',
      (Request q, String id) =>
          _guard(q, (q, u) => _copyArticle(q, u, Uri.decodeComponent(id))),
    );
    for (final method in ['GET', 'PUT']) {
      r.add(
        method,
        '/projects/<id>/drawing',
        (Request q, String id) =>
            _guard(q, (q, u) => _drawing(q, u, Uri.decodeComponent(id))),
      );
    }
    r.get(
      '/projects/<id>/drawing/history',
      (Request q, String id) =>
          _guard(q, (q, u) => _drawingHistory(q, u, Uri.decodeComponent(id))),
    );
    r.get(
      '/projects/<id>/drawing/export',
      (Request q, String id) =>
          _guard(q, (q, u) => _drawingExport(q, u, Uri.decodeComponent(id))),
    );
    r.get(
      '/projects/<id>/documents',
      (Request q, String id) => _guard(q, (q, u) => _documents(q, u, id)),
    );
    r.get(
      '/projects/<id>/releases',
      (Request q, String id) => _guard(q, (q, u) => _releases(q, u, id)),
    );
    r.post(
      '/projects/<id>/releases',
      (Request q, String id) => _guard(q, (q, u) => _approve(q, u, id)),
    );
    r.post(
      '/projects/<id>/offline',
      (Request q, String id) => _guard(q, (q, u) => _offline(q, u, id)),
    );
    r.post(
      '/projects/<id>/offline/upload',
      (Request q, String id) => _guard(q, (q, u) => _offlineUpload(q, u, id)),
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
    } on FileSystemException {
      return jsonError(
        'Projektarchiv nicht verfügbar. Freigabestatus neu laden; Arbeitsstände bleiben erhalten.',
        status: 503,
      );
    } on ProcessException {
      return jsonError('Git-Archiv nicht verfügbar.', status: 503);
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
      if (bytes.length > 4194304)
        throw FormatException('Anfrage zu groß (max. 4 MiB).');
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
  Future<bool> _projectVisible(Document p, AppUser u) =>
      projectVisible(store, p, u);
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
    for (final e in old.entries)
      if (e.key != 'release') e.key: e.value,
    'version': (old['version'] as int) + 1,
    'updatedBy': u.id,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Response _conflict() => jsonError(
    'Stand wurde geändert. Neu laden, Änderungen vergleichen und bewusst erneut speichern.',
    status: 409,
  );

  Future<Response> _listGroups(Request q, AppUser u) async => jsonOk({
    'groups': [
      for (final g in await store.list(u.companyId, 'projectGroup'))
        if (_admin(u) || (g['memberIds'] as List).contains(u.id))
          {
            for (final e in g.entries)
              if (_admin(u) || e.key != 'memberIds') e.key: e.value,
          },
    ],
  });

  Future<Response> _saveGroup(Request q, AppUser u, [String? id]) async {
    if (!_admin(u))
      return jsonError(
        'Nur Firmenadmins verwalten Projektgruppen.',
        status: 403,
      );
    final body = await _body(q);
    final old = id == null
        ? null
        : await store.get(u.companyId, 'projectGroup', id);
    if (id != null && old == null)
      return jsonError('Gruppe nicht gefunden.', status: 404);
    if (old != null && body['version'] != old['version']) return _conflict();
    final group = {
      ...old == null ? _newDocument(u) : _revision(old, u),
      'name': _text(body, 'name'),
      'description': _text(body, 'description', max: 4000, optional: true),
      'memberIds': await _members(body, u),
    };
    if (old == null) {
      await store.create(u.companyId, 'projectGroup', group);
    } else if (!await store.update(
      u.companyId,
      'projectGroup',
      group,
      old['version'],
    )) {
      return _conflict();
    }
    return jsonOk(group, status: old == null ? 201 : 200);
  }

  Future<List<String>> _groups(Document body, AppUser u) async {
    final ids = body['groupIds'] ?? <String>[];
    if (ids is! List || ids.length > 100 || ids.any((id) => id is! String)) {
      throw FormatException('groupIds: maximal 100 Gruppen-IDs.');
    }
    for (final id in ids) {
      if (await store.get(u.companyId, 'projectGroup', id) == null) {
        throw FormatException(
          'Projektgruppen müssen zur eigenen Firma gehören.',
        );
      }
    }
    return ids.cast<String>().toSet().toList();
  }

  Future<Response> _listProjects(Request q, AppUser u) async => jsonOk({
    'projects': [
      for (final p in await store.list(u.companyId, 'project'))
        if (await _projectVisible(p, u)) p,
    ],
  });

  Future<Response> _createProject(Request q, AppUser u) async {
    if (!_admin(u))
      return jsonError('Nur Firmenadmins legen Projekte an.', status: 403);
    final d = await _body(q);
    final p = {
      ..._newDocument(u),
      'name': _text(d, 'name'),
      'description': _text(d, 'description', max: 4000, optional: true),
      'metadata': _metadata(d['metadata']),
      'memberIds': await _members(d, u),
      'groupIds': await _groups(d, u),
    };
    await store.create(u.companyId, 'project', p);
    return jsonOk(p, status: 201);
  }

  Future<Response> _project(Request q, AppUser u, String id) async {
    final p = await store.get(u.companyId, 'project', id);
    if (p == null || !await _projectVisible(p, u))
      return jsonError('Projekt nicht gefunden.', status: 404);
    if (q.method == 'GET') return jsonOk(p);
    final d = await _body(q);
    if (d['version'] is! int) throw FormatException('version ist Pflicht.');
    if (d['version'] != p['version']) return _conflict();
    if (!_admin(u) && (d.containsKey('memberIds') || d.containsKey('groupIds')))
      return jsonError('Nur Firmenadmins verwalten Mitglieder.', status: 403);
    final next = {
      ..._revision(p, u),
      'name': _text(d, 'name'),
      'description': _text(d, 'description', max: 4000, optional: true),
      'metadata': d.containsKey('metadata')
          ? _metadata(d['metadata'])
          : p['metadata'] ?? <String, dynamic>{},
      'memberIds': _admin(u) && d.containsKey('memberIds')
          ? await _members(d, u)
          : p['memberIds'],
      'groupIds': d.containsKey('groupIds')
          ? await _groups(d, u)
          : p['groupIds'] ?? <String>[],
    };
    if (!await store.update(u.companyId, 'project', next, d['version'] as int))
      return _conflict();
    return jsonOk(next);
  }

  Future<Response> _offline(Request q, AppUser u, String id) async {
    final p = await _drawingProject(id, u);
    if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
    final body = await _body(q);
    if (body['confirmed'] != true)
      throw FormatException('Offline-Download bewusst bestätigen.');
    if (p['drawing'] == null)
      throw FormatException('Zuerst eine Zeichnung speichern.');
    final hours =
        int.tryParse(Platform.environment['OFFLINE_LEASE_HOURS'] ?? '24') ?? 24;
    if (hours < 1 || hours > 168)
      throw StateError('OFFLINE_LEASE_HOURS must be 1..168');
    final now = DateTime.now().toUtc();
    final company = await users.findCompanyById(u.companyId);
    return jsonOk({
      'format': 'libre-ecad-offline-v1',
      'id': SessionTokens.generate(),
      'userId': u.id,
      'companyId': u.companyId,
      'username': u.username,
      'companyName': company!.name,
      'issuedAt': now.toIso8601String(),
      'expiresAt': now.add(Duration(hours: hours)).toIso8601String(),
      'baseVersion': p['version'],
      'project': _publicProject(p),
      'library': pinnedLibrary(),
      'localRevision': 0,
    });
  }

  Future<Response> _offlineUpload(Request q, AppUser u, String id) async {
    final p = await _drawingProject(id, u);
    if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
    final body = await _body(q);
    if (body['confirmed'] != true)
      throw FormatException('Upload bewusst bestätigen.');
    if (body['userId'] != u.id || body['companyId'] != u.companyId)
      return jsonError(
        'Offline-Kopie gehört zu einem anderen Zugang.',
        status: 403,
      );
    if (body['version'] is! int || body['version'] != p['version'])
      return _conflict();
    if (body['baseVersion'] is! int ||
        body['baseVersion'] < 1 ||
        body['baseVersion'] > body['version']) {
      throw FormatException('Ungültiger Offline-Basisstand.');
    }
    final drawing = validateDrawing(body['drawing']);
    final next = {
      ..._revision(p, u),
      'drawing': drawing,
      'activity': {
        'action': 'offline-upload',
        'baseVersion': body['baseVersion'],
        'expectedVersion': body['version'],
        'confirmedBy': u.id,
      },
    };
    if (!await store.update(u.companyId, 'project', next, body['version']))
      return _conflict();
    return jsonOk(_drawingResponse(next));
  }

  Document _metadata(Object? input) {
    if (input == null) return {};
    if (input is! Map<String, dynamic>)
      throw FormatException('metadata muss ein Objekt sein.');
    const allowed = [
      'Kunde',
      'Anlage',
      'Auftrag',
      'Baujahr',
      'Standort',
      'Verantwortlich',
      'Dokumentnummer',
    ];
    if (input.keys.any((k) => !allowed.contains(k)))
      throw FormatException('Unbekanntes Metadatenfeld.');
    return {
      for (final k in input.keys) k: _text(input, k, max: 160, optional: true),
    };
  }

  GitArchive get _archive => GitArchive(
    Platform.environment['PROJECT_ARCHIVE_DIR'] ??
        '${Directory.systemTemp.path}/libre-ecad-archives',
  );
  Document _publicProject(Document p) => {
    for (final key in [
      'id',
      'name',
      'description',
      'metadata',
      'version',
      'drawing',
    ])
      if (p.containsKey(key)) key: p[key],
  };
  Document _releaseSummary(Document packet) => {
    for (final key in [
      'id',
      'version',
      'at',
      'username',
      'reason',
      'commit',
      'sha256',
    ])
      key: packet[key],
  };
  Future<List<Document>> _packets(AppUser u, String id) async => [
    for (final p in await store.history(u.companyId, 'project', id))
      if (p['release'] is Map) Map<String, dynamic>.from(p['release']),
  ];
  Future<Response> _releases(Request q, AppUser u, String id) async {
    if (await _drawingProject(id, u) == null)
      return jsonError('Projekt nicht gefunden.', status: 404);
    return jsonOk({
      'releases': (await _packets(u, id)).map(_releaseSummary).toList(),
    });
  }

  Future<Response> _documents(Request q, AppUser u, String id) async {
    final current = await _drawingProject(id, u);
    if (current == null)
      return jsonError('Projekt nicht gefunden.', status: 404);
    final query = q.url.queryParameters;
    if (query['release'] != null) {
      final packets = await _packets(u, id);
      final packet = packets
          .where((p) => p['id'] == query['release'])
          .firstOrNull;
      if (packet == null)
        return jsonError(
          'Festgeschriebener Stand nicht gefunden.',
          status: 404,
        );
      for (final p in packets) {
        await _archive.write(u.companyId, id, p);
        if (p['id'] == packet['id']) break;
      }
      final files = packet['files'] as Map;
      final project =
          jsonDecode(utf8.decode(base64Decode(files['project.json'])))
              as Document;
      final data =
          jsonDecode(utf8.decode(base64Decode(files['documents.json'])))
              as Document;
      return jsonOk({
        'source': 'release',
        'project': project,
        'data': data,
        'findings': files['checks.json'] == null
            ? drawingFindings(project['drawing'])
            : jsonDecode(
                utf8.decode(base64Decode(files['checks.json'])),
              )['findings'],
        'approval': jsonDecode(
          utf8.decode(base64Decode(files['approval.json'])),
        ),
        'release': _releaseSummary(packet),
        'pdf': files['output.pdf'],
      });
    }
    final version = int.tryParse(query['version'] ?? '');
    if (version == null)
      throw FormatException('Arbeitsversion ausdrücklich wählen.');
    final selected = (await store.history(
      u.companyId,
      'project',
      id,
    )).where((p) => p['version'] == version).firstOrNull;
    if (selected == null || selected['drawing'] == null)
      return jsonError(
        'Gespeicherte Zeichnungsversion nicht gefunden.',
        status: 404,
      );
    final project = _publicProject(selected);
    final data = documentData(project);
    return jsonOk({
      'source': 'working',
      'project': project,
      'data': data,
      'findings': drawingFindings(project['drawing']),
      'pdf': base64Encode(
        await projectPdf(
          project,
          status: 'ARBEITSSTAND - NICHT FREIGEGEBEN',
          stamp: 'V$version',
        ),
      ),
    });
  }

  Future<Response> _approve(Request q, AppUser u, String id) async {
    final project = await _drawingProject(id, u);
    if (project == null)
      return jsonError('Projekt nicht gefunden.', status: 404);
    if (!_admin(u))
      return jsonError(
        'Nur Firmenadmins schreiben einen Stand fachlich fest.',
        status: 403,
      );
    final body = await _body(q);
    if (body['version'] is! int) throw FormatException('version ist Pflicht.');
    if (body['version'] != project['version']) return _conflict();
    if (body['confirmed'] != true)
      throw FormatException('Explizite fachliche Bestätigung fehlt.');
    final reason = _text(body, 'reason', max: 1000);
    final findings = drawingFindings(project['drawing']);
    if (findings.any((f) => f['severity'] == 'error'))
      throw FormatException('Strukturfehler verhindern die Freigabe.');
    final exceptions = body['exceptions'];
    if (exceptions is! Map<String, dynamic>)
      throw FormatException('Begründete Ausnahmen fehlen.');
    final findingIds = findings.map((f) => f['id']).toSet();
    if (exceptions.keys.any((k) => !findingIds.contains(k)))
      throw FormatException('Ausnahmen gehören nicht zu dieser Version.');
    for (final f in findings) {
      _text(exceptions, f['id'], max: 1000);
    }
    final releaseId = SessionTokens.generate();
    final at = DateTime.now().toUtc().toIso8601String();
    final approval = {
      'id': releaseId,
      'at': at,
      'username': u.username,
      'userId': u.id,
      'reason': reason,
      'exceptions': exceptions,
      'version': project['version'],
    };
    final public = _publicProject(project), data = documentData(public);
    final pdf = await projectPdf(
      public,
      status: 'FACHLICH FESTGESCHRIEBEN',
      stamp: releaseId.substring(0, 8),
      approval: approval,
    );
    final files = <String, dynamic>{
      'project.json': base64Encode(utf8.encode(canonicalJson(public))),
      'documents.json': base64Encode(utf8.encode(canonicalJson(data))),
      'checks.json': base64Encode(
        utf8.encode(
          canonicalJson({
            'rulesVersion': 'synthetic-checks-1',
            'findings': findings,
          }),
        ),
      ),
      'library.json': base64Encode(utf8.encode(canonicalJson(pinnedLibrary()))),
      'approval.json': base64Encode(utf8.encode(canonicalJson(approval))),
      'output.pdf': base64Encode(pdf),
      for (final sheet in objects(public['drawing'], 'sheets'))
        'sheet-${sheet['number']}.svg': base64Encode(
          utf8.encode(sheetSvg(public['drawing'], sheet['id'])),
        ),
    };
    final hashes = {
      for (final e in files.entries)
        e.key: sha256.convert(base64Decode(e.value)).toString(),
    };
    files['manifest.json'] = base64Encode(
      utf8.encode(
        canonicalJson({'format': 'libre-ecad-release-v1', 'files': hashes}),
      ),
    );
    final previous = await _packets(u, id);
    // Rebuild missing Git objects after SQL-only recovery before parenting a commit.
    for (final p in previous) {
      await _archive.write(u.companyId, id, p);
    }
    final packet = <String, dynamic>{
      ...approval,
      'parent': previous.lastOrNull?['commit'],
      'files': files,
      'sha256': hashes['output.pdf'],
    };
    packet['commit'] = await _archive.write(u.companyId, id, packet);
    final next = {..._revision(project, u), 'release': packet};
    // Git candidates are not approvals. Only this atomic SQL history entry publishes one.
    if (!await store.update(u.companyId, 'project', next, body['version']))
      return _conflict();
    return jsonOk({
      'release': _releaseSummary(packet),
      'version': next['version'],
    }, status: 201);
  }

  Future<Document?> _drawingProject(String id, AppUser u) async {
    final p = await store.get(u.companyId, 'project', id);
    return p != null && await _projectVisible(p, u) ? p : null;
  }

  Document _drawingResponse(Document p) {
    final drawing = p['drawing'];
    return {
      'projectId': p['id'],
      'projectName': p['name'],
      'version': p['version'],
      'drawing': drawing,
      'nets': drawing == null ? <Document>[] : nets(drawing as Document),
      'updatedAt': p['updatedAt'],
      'updatedBy': p['updatedBy'],
    };
  }

  Future<Response> _drawing(Request q, AppUser u, String id) async {
    final p = await _drawingProject(id, u);
    if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
    if (q.method == 'GET') return jsonOk(_drawingResponse(p));
    final body = await _body(q);
    if (body['version'] is! int) throw FormatException('version ist Pflicht.');
    if (body['version'] != p['version']) return _conflict();
    final drawing = validateDrawing(body['drawing']);
    final next = {..._revision(p, u), 'drawing': drawing};
    if (!await store.update(
      u.companyId,
      'project',
      next,
      body['version'] as int,
    ))
      return _conflict();
    return jsonOk(_drawingResponse(next));
  }

  Future<Response> _drawingHistory(Request q, AppUser u, String id) async {
    if (await _drawingProject(id, u) == null)
      return jsonError('Projekt nicht gefunden.', status: 404);
    return jsonOk({
      'versions': (await store.history(
        u.companyId,
        'project',
        id,
      )).where((p) => p['drawing'] != null).map(_drawingResponse).toList(),
    });
  }

  Future<Response> _drawingExport(Request q, AppUser u, String id) async {
    final p = await _drawingProject(id, u);
    if (p == null) return jsonError('Projekt nicht gefunden.', status: 404);
    final snapshot = <String, dynamic>{
      'format': 'libre-ecad-workspace-v1',
      'state': 'unapproved-working-copy',
      'projectId': p['id'],
      'name': p['name'],
      'description': p['description'],
      'version': p['version'],
      'drawing': p['drawing'],
    };
    final content = canonicalJson(snapshot);
    return jsonOk({
      'content': content,
      'sha256': sha256.convert(utf8.encode(content)).toString(),
      'version': p['version'],
    });
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
      'license':
          source['license'] ?? 'Ungeklärt – synthetische Katalog-Beispieldaten',
      'origin':
          source['origin'] ??
          'Globaler Katalog / ${source['source']} / ${source['manufacturerName'] ?? "Allgemein"}',
      'notes': source['attribution'] == null
          ? 'Synthetische Katalogmetadaten; technische Ebenen fehlen. Keine Herstellerverifikation.'
          : 'Namensnennung: ${source['attribution']}. Technische Werte ungeprüft.',
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
