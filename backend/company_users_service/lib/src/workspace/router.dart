import 'dart:convert';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models.dart';
import '../repository.dart';
import 'store.dart';

class WorkspaceRouter {
  WorkspaceRouter({
    required this.store,
    required this.users,
    required this.authenticate,
  });
  final WorkspaceStore store;
  final CompanyUserRepository users;
  final Future<AppUser?> Function(Request) authenticate;

  Router get handler {
    final r = Router();
    r.get('/projects', (Request q) => _guard(q, _listProjects));
    r.post('/projects', (Request q) => _guard(q, _createProject));
    r.get(
      '/projects/<id>',
      (Request q, String id) => _guard(q, (q, u) => _project(q, u, id)),
    );
    r.patch(
      '/projects/<id>',
      (Request q, String id) => _guard(q, (q, u) => _project(q, u, id)),
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
}
