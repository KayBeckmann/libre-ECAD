import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:shared_server_kit/shared_server_kit.dart' hide cloneJson;
import 'package:company_users_service/src/models.dart';
import 'package:company_users_service/src/repository_memory.dart';
import 'package:company_users_service/src/router.dart';
import 'package:company_users_service/src/workspace/store.dart';
import 'package:company_users_service/src/workspace/global_catalog.dart';

void main() {
  late InMemoryCompanyUserRepository users;
  late MemoryWorkspaceStore store;
  late Handler handler;
  var globalAvailable = true;
  final tokens = <String, String>{};
  Future<void> account(String id, String company, UserRole role) async {
    final created = await users.createUser(
      id: id,
      companyId: company,
      username: id,
      role: role,
    );
    await users.activateWithToken(
      rawToken: created.rawActivationToken,
      passwordHash: 'test-hash',
    );
    final token = SessionTokens.generate();
    tokens[id] = token;
    await users.saveSession(
      UserSession(
        tokenHash: SessionTokens.hashOf(token),
        userId: id,
        companyId: company,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  Future<Response> call(
    String user,
    String method,
    String path, [
    Object? body,
  ]) async => handler(
    Request(
      method,
      Uri.parse('http://localhost/api/v1/$path'),
      headers: {'authorization': 'Bearer ${tokens[user]}'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  setUp(() async {
    users = InMemoryCompanyUserRepository();
    store = MemoryWorkspaceStore();
    globalAvailable = true;
    await users.createCompany(id: 'a', name: 'Firma A');
    await users.createCompany(id: 'b', name: 'Firma B');
    await account('admin-a', 'a', UserRole.admin);
    await account('admin-b', 'b', UserRole.admin);
    await account('drafter-a', 'a', UserRole.zeichner);
    handler = CompanyUserRouter(
      repository: users,
      internalToken: 'test',
      workspace: store,
      automationRecords: MemoryRecords(),
      globalLookup: (id) async {
        if (!globalAvailable) throw GlobalCatalogUnavailable();
        return {
          'id': id,
          'articleNumber': 'SAMPLE',
          'name': 'Beispieldaten',
          'version': 1,
          'source': 'manufacturer',
          'manufacturerName': 'ACME',
        };
      },
    ).handler.call;
  });
  test(
    'macro privacy, version conflict, copies and shared company read permissions',
    () async {
      final body = {
        'scope': 'personal',
        'name': 'Motorstarter',
        'origin': 'Own TEST',
        'license': 'CC0-1.0',
        'groups': ['Schaltanlagen'],
        'drawing': sampleDrawing('motor'),
      };
      final created = await call('drafter-a', 'POST', 'macros/', body);
      expect(created.statusCode, 201);
      final a = await json(created);
      for (final user in ['admin-a', 'admin-b'])
        expect((await call(user, 'GET', 'macros/${a['id']}')).statusCode, 404);
      expect(
        (await call('drafter-a', 'POST', 'macros/${a['id']}/copy', {
          'scope': 'company',
          'version': 1,
        })).statusCode,
        403,
      );
      final own = await json(
        await call('admin-a', 'POST', 'macros/', {...body, 'scope': 'company'}),
      );
      expect(
        (await call('drafter-a', 'GET', 'macros/${own['id']}')).statusCode,
        200,
      );
      expect(
        (await call('drafter-a', 'PATCH', 'macros/${own['id']}', {
          ...body,
          'version': 1,
        })).statusCode,
        403,
      );
      expect(
        (await call('admin-a', 'PATCH', 'macros/${own['id']}', {
          ...body,
          'name': 'Revision',
          'version': 1,
        })).statusCode,
        200,
      );
      expect(
        (await call('admin-a', 'PATCH', 'macros/${own['id']}', {
          ...body,
          'version': 1,
        })).statusCode,
        409,
      );
      final copy = await json(
        await call('drafter-a', 'POST', 'macros/${own['id']}/copy', {
          'scope': 'personal',
          'version': 2,
        }),
      );
      expect(copy['source']['version'], 2);
      expect(copy['id'], isNot(own['id']));
      expect(
        (await json(
          await call('admin-a', 'GET', 'macros/${own['id']}/history'),
        ))['versions'],
        hasLength(2),
      );
    },
  );
  test(
    'same project names do not cross company boundaries, including direct IDs',
    () async {
      final a = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Verteilung'}),
      );
      final b = await json(
        await call('admin-b', 'POST', 'projects', {'name': 'Verteilung'}),
      );
      expect(a['id'], isNot(b['id']));
      final own = await json(await call('admin-a', 'GET', 'projects'));
      expect((own['projects'] as List).length, 1);
      expect(
        (await call('admin-a', 'GET', 'projects/${b['id']}')).statusCode,
        404,
      );
      expect(
        (await call('admin-a', 'PATCH', 'projects/${b['id']}', {
          'name': 'Hacked',
          'version': 1,
        })).statusCode,
        404,
      );
    },
  );
  test(
    'drafter needs membership; cannot create projects or grant membership',
    () async {
      final p = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Test'}),
      );
      expect(
        (await call('drafter-a', 'GET', 'projects/${p['id']}')).statusCode,
        404,
      );
      expect(
        (await call('drafter-a', 'POST', 'projects', {
          'name': 'Test',
        })).statusCode,
        403,
      );
      expect(
        (await call('admin-a', 'PATCH', 'projects/${p['id']}', {
          ...p,
          'memberIds': ['drafter-a'],
        })).statusCode,
        200,
      );
      expect(
        (await call('drafter-a', 'GET', 'projects/${p['id']}')).statusCode,
        200,
      );
      expect(
        (await call('drafter-a', 'PATCH', 'projects/${p['id']}', {
          'name': 'Test',
          'version': 2,
          'memberIds': [],
        })).statusCode,
        403,
      );
      expect(
        (await call('drafter-a', 'PATCH', 'projects/${p['id']}', {
          'name': 'Changed',
          'version': 2,
        })).statusCode,
        200,
      );
    },
  );
  test(
    'stale updates return conflict and keep newer data and history intact',
    () async {
      final p = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Original'}),
      );
      expect(
        (await call('admin-a', 'PATCH', 'projects/${p['id']}', {
          'name': 'New',
          'version': 1,
        })).statusCode,
        200,
      );
      expect(
        (await call('admin-a', 'PATCH', 'projects/${p['id']}', {
          'name': 'Stale',
          'version': 1,
        })).statusCode,
        409,
      );
      expect(
        (await json(
          await call('admin-a', 'GET', 'projects/${p['id']}'),
        ))['name'],
        'New',
      );
      expect(
        (await store.history('a', 'project', p['id'] as String)).length,
        2,
      );
    },
  );
  test(
    'foreign members and malformed data are rejected without persistence',
    () async {
      expect(
        (await call('admin-a', 'POST', 'projects', {
          'name': 'Test',
          'memberIds': ['admin-b'],
        })).statusCode,
        400,
      );
      expect(
        (await call('admin-a', 'POST', 'projects', {'name': 42})).statusCode,
        400,
      );
      expect((await call('admin-a', 'POST', 'projects', [])).statusCode, 400);
      expect(await store.list('a', 'project'), isEmpty);
    },
  );
  test('deactivated user cannot use a previously issued session', () async {
    await users.setUserActive(id: 'drafter-a', active: false);
    expect((await call('drafter-a', 'GET', 'projects')).statusCode, 401);
  });
  test(
    'drawing revision, ACL, history, rejected conflicts and deterministic export',
    () async {
      final p = await json(
        await call('admin-a', 'POST', 'projects', {
          'name': 'CAD',
          'memberIds': ['drafter-a'],
        }),
      );
      final path = 'projects/${p['id']}/drawing';
      final drawing = sampleDrawing('motor');
      expect(
        (await json(await call('drafter-a', 'GET', path)))['drawing'],
        isNull,
      );
      expect(
        (await call('drafter-a', 'PUT', path, {
          'version': 1,
          'drawing': drawing,
        })).statusCode,
        200,
      );
      for (final suffix in ['', '/history', '/export']) {
        expect((await call('admin-b', 'GET', '$path$suffix')).statusCode, 404);
      }
      expect(
        (await call('admin-b', 'PUT', path, {
          'version': 2,
          'drawing': drawing,
        })).statusCode,
        404,
      );
      expect(
        (await call('admin-a', 'PUT', path, {
          'version': 1,
          'drawing': drawing,
        })).statusCode,
        409,
      );
      final invalid = cloneJson(drawing);
      objects(invalid, 'instances').first['deviceId'] = 'missing';
      expect(
        (await call('admin-a', 'PUT', path, {
          'version': 2,
          'drawing': invalid,
        })).statusCode,
        400,
      );
      final saved = await json(await call('admin-a', 'GET', path));
      expect(saved['drawing'], drawing);
      expect(saved['version'], 2);
      final snapshot = await json(await call('admin-a', 'GET', '$path/export'));
      expect(
        snapshot,
        await json(await call('admin-a', 'GET', '$path/export')),
      );
      expect(
        jsonDecode(snapshot['content'])['state'],
        'unapproved-working-copy',
      );
      expect(
        (await json(await call('admin-a', 'GET', '$path/history')))['versions'],
        hasLength(1),
      );
      expect(
        (await call('admin-a', 'PATCH', 'projects/${p['id']}', {
          'name': 'CAD',
          'memberIds': [],
          'version': 2,
        })).statusCode,
        200,
      );
      expect(
        (await call('drafter-a', 'PUT', path, {
          'version': 3,
          'drawing': drawing,
        })).statusCode,
        404,
      );
      expect((await call('drafter-a', 'GET', '$path/history')).statusCode, 404);
      // Restoring content is an explicit new CAS revision, never rewriting history.
      final next = cloneJson(drawing);
      objects(next, 'devices').first['bmk'] = 'RENAMED';
      expect(
        (await call('admin-a', 'PUT', path, {
          'version': 3,
          'drawing': next,
        })).statusCode,
        200,
      );
      expect(
        (await call('admin-a', 'PUT', path, {
          'version': 4,
          'drawing': drawing,
        })).statusCode,
        200,
      );
      final history =
          (await json(
                await call('admin-a', 'GET', '$path/history'),
              ))['versions']
              as List;
      expect(history.map((v) => v['version']), [2, 3, 4, 5]);
      expect(history.first['drawing'], drawing);
      expect(history.last['drawing'], drawing);
    },
  );
  Map<String, dynamic> article({String scope = 'personal'}) => {
    'scope': scope,
    'articleNumber': 'TEST-16',
    'name': 'Synthetischer Testschalter',
    'origin': 'Eigener Testentwurf',
    'license': 'CC0',
    'layers': {
      'symbol': {
        'reference': 'Eigener Testblock',
        'license': 'CC0',
        'terminals': [
          {'id': '1', 'label': 'L'},
        ],
      },
      'mechanical': {'widthMm': 18},
      'electrical': {'voltageV': 230, 'currentA': 16},
      'thermal': {'powerLossW': 0},
    },
  };
  test('article symbol geometry is versioned, copied and validated', () async {
    final body = article();
    final symbol = symbolTemplate('contact_nc', 'test-symbol');
    body['layers']['symbol']['definition'] = symbol;
    body['layers']['symbol']['terminals'] = [
      for (final p in symbol['ports']) {'id': p['id'], 'label': p['label']},
    ];
    final created = await call('admin-a', 'POST', 'articles', body);
    expect(created.statusCode, 201);
    final a = await json(created);
    expect(a['layers']['symbol']['definition'], symbol);
    final copy = await json(
      await call('admin-a', 'POST', 'articles/${a['id']}/copy', {
        'scope': 'company',
        'version': 1,
      }),
    );
    symbol['name'] = 'Geänderter Öffner';
    final updated = await call('admin-a', 'PATCH', 'articles/${a['id']}', {
      ...body,
      'version': 1,
    });
    expect(updated.statusCode, 200);
    expect((await json(updated))['version'], 2);
    expect(
      copy['layers']['symbol']['definition']['name'],
      isNot(symbol['name']),
    );
    expect(
      (await call('admin-b', 'GET', 'articles/${a['id']}')).statusCode,
      404,
    );
    body['layers']['symbol']['terminals'] = [
      {'id': 'wrong', 'label': 'wrong'},
    ];
    expect(
      (await call('admin-a', 'PATCH', 'articles/${a['id']}', {
        ...body,
        'version': 2,
      })).statusCode,
      400,
    );
    body['layers']['symbol']['terminals'] = [
      for (final p in symbol['ports']) {'id': p['id'], 'label': p['label']},
    ];
    symbol['primitives'].add({'kind': 'svg', 'url': 'https://invalid'});
    expect(
      (await call('admin-a', 'PATCH', 'articles/${a['id']}', {
        ...body,
        'version': 2,
      })).statusCode,
      400,
    );
  });
  test(
    'personal articles are private even from another admin; cross-company IDs remain hidden',
    () async {
      final r = await call('drafter-a', 'POST', 'articles', article());
      expect(r.statusCode, 201);
      final a = await json(r);
      for (final user in ['admin-a', 'admin-b']) {
        expect(
          (await call(user, 'GET', 'articles/${a['id']}')).statusCode,
          404,
        );
        expect(
          (await call(user, 'GET', 'articles/${a['id']}/history')).statusCode,
          404,
        );
        expect(
          (await call(user, 'POST', 'articles/${a['id']}/copy', {
            'scope': 'personal',
            'version': 1,
          })).statusCode,
          404,
        );
      }
      expect(
        (await json(await call('admin-a', 'GET', 'articles')))['articles'],
        isEmpty,
      );
    },
  );
  test(
    'company catalog is readable by drafters but writable only by admins',
    () async {
      final a = await json(
        await call('admin-a', 'POST', 'articles', article(scope: 'company')),
      );
      expect(
        (await call('drafter-a', 'GET', 'articles/${a['id']}')).statusCode,
        200,
      );
      expect(
        (await call('drafter-a', 'PATCH', 'articles/${a['id']}', {
          ...article(),
          'version': 1,
        })).statusCode,
        403,
      );
      expect(
        (await call(
          'drafter-a',
          'POST',
          'articles',
          article(scope: 'company'),
        )).statusCode,
        403,
      );
      expect(
        (await call('admin-b', 'GET', 'articles/${a['id']}')).statusCode,
        404,
      );
    },
  );
  test(
    'copy pins provenance, stays independent, and preserves old versions',
    () async {
      final a = await json(
        await call('admin-a', 'POST', 'articles', article()),
      );
      final copy = await json(
        await call('admin-a', 'POST', 'articles/${a['id']}/copy', {
          'scope': 'company',
          'version': 1,
        }),
      );
      expect(copy['id'], isNot(a['id']));
      expect(copy['source']['articleId'], a['id']);
      expect(copy['source']['version'], 1);
      final changed = await json(
        await call('admin-a', 'PATCH', 'articles/${a['id']}', {
          ...article(),
          'name': 'Neu',
          'version': 1,
        }),
      );
      expect(changed['layers']['symbol']['id'], a['layers']['symbol']['id']);
      expect(
        copy['layers']['symbol']['id'],
        isNot(a['layers']['symbol']['id']),
      );
      expect(
        (await json(
          await call('admin-a', 'GET', 'articles/${copy['id']}'),
        ))['name'],
        a['name'],
      );
      expect(
        (await call('admin-a', 'PATCH', 'articles/${a['id']}', {
          ...article(),
          'name': 'Veraltet',
          'version': 1,
        })).statusCode,
        409,
      );
      final history = await json(
        await call('admin-a', 'GET', 'articles/${a['id']}/history'),
      );
      expect((history['versions'] as List).map((v) => v['name']), [
        a['name'],
        'Neu',
      ]);
    },
  );
  test(
    'missing numeric data stays unknown; zero stays zero; duplicate terminals rejected',
    () async {
      final a = await json(
        await call('admin-a', 'POST', 'articles', article()),
      );
      expect(a['layers']['mechanical']['heightMm'], isNull);
      expect(a['layers']['thermal']['powerLossW'], 0);
      expect(a['warnings'], contains('Höhe [mm] fehlt'));
      final invalid = article();
      invalid['layers']['symbol']['terminals'] = [
        {'id': '1', 'label': 'a'},
        {'id': '1', 'label': 'b'},
      ];
      expect(
        (await call('admin-a', 'POST', 'articles', invalid)).statusCode,
        400,
      );
      invalid['layers']['symbol']['terminals'] = [];
      invalid['layers']['mechanical']['widthMm'] = -1;
      expect(
        (await call('admin-a', 'POST', 'articles', invalid)).statusCode,
        400,
      );
    },
  );
  test(
    'local search separates scopes and finds article number or name',
    () async {
      await call('admin-a', 'POST', 'articles', article());
      await call('admin-a', 'POST', 'articles', article(scope: 'company'));
      final personal = await json(
        await call('admin-a', 'GET', 'articles?scope=personal&query=test-16'),
      );
      final company = await json(
        await call(
          'admin-a',
          'GET',
          'articles?scope=company&query=Testschalter',
        ),
      );
      expect((personal['articles'] as List).length, 1);
      expect((company['articles'] as List).length, 1);
      expect(
        (await json(
          await call('admin-a', 'GET', 'articles?query=absent'),
        ))['articles'],
        isEmpty,
      );
    },
  );
  test(
    'global failure and stale source version never create or mutate local data',
    () async {
      final original = await json(
        await call('admin-a', 'POST', 'articles', article()),
      );
      globalAvailable = false;
      expect(
        (await call('admin-a', 'POST', 'global-articles/sample/copy', {
          'scope': 'personal',
          'version': 1,
        })).statusCode,
        503,
      );
      expect((await store.list('a', 'article')).length, 1);
      expect(
        (await json(
          await call('admin-a', 'GET', 'articles/${original['id']}'),
        ))['version'],
        1,
      );
      globalAvailable = true;
      expect(
        (await call('admin-a', 'POST', 'global-articles/sample/copy', {
          'scope': 'personal',
          'version': 0,
        })).statusCode,
        409,
      );
      final copy = await json(
        await call('admin-a', 'POST', 'global-articles/sample/copy', {
          'scope': 'personal',
          'version': 1,
        }),
      );
      expect(copy['source']['kind'], 'global');
      expect(copy['source']['area'], 'manufacturer');
      expect(copy['layers']['electrical']['status'], 'unverified');
      expect(copy['layers']['electrical']['voltageV'], isNull);
      expect(
        (await call('drafter-a', 'POST', 'global-articles/sample/copy', {
          'scope': 'company',
          'version': 1,
        })).statusCode,
        403,
      );
    },
  );
  test(
    'offline download and explicit CAS upload enforce membership and identity',
    () async {
      var p = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Offline'}),
      );
      final id = p['id'];
      await call('admin-a', 'PUT', 'projects/$id/drawing', {
        'version': 1,
        'drawing': sampleDrawing('motor'),
      });
      expect(
        (await call('admin-a', 'POST', 'projects/$id/offline', {})).statusCode,
        400,
      );
      expect(
        (await call('admin-b', 'POST', 'projects/$id/offline', {
          'confirmed': true,
        })).statusCode,
        404,
      );
      expect(
        (await call('drafter-a', 'POST', 'projects/$id/offline', {
          'confirmed': true,
        })).statusCode,
        404,
      );
      final packet = await json(
        await call('admin-a', 'POST', 'projects/$id/offline', {
          'confirmed': true,
        }),
      );
      expect(packet['baseVersion'], 2);
      expect(packet['library'], pinnedLibrary());
      expect(packet.containsKey('token'), isFalse);
      final upload = {
        'confirmed': true,
        'userId': 'admin-a',
        'companyId': 'a',
        'version': 2,
        'baseVersion': 2,
        'drawing': sampleDrawing('distribution'),
      };
      expect(
        (await call('admin-a', 'POST', 'projects/$id/offline/upload', {
          ...upload,
          'confirmed': false,
        })).statusCode,
        400,
      );
      expect(
        (await call('admin-a', 'POST', 'projects/$id/offline/upload', {
          ...upload,
          'userId': 'drafter-a',
        })).statusCode,
        403,
      );
      final responses = await Future.wait(
        List.generate(
          2,
          (_) => call('admin-a', 'POST', 'projects/$id/offline/upload', upload),
        ),
      );
      expect(responses.map((r) => r.statusCode).toList()..sort(), [200, 409]);
      p = (await store.get('a', 'project', id))!;
      expect(p['activity']['confirmedBy'], 'admin-a');
      expect(p['version'], 3);
      await call('admin-a', 'PATCH', 'projects/$id', {
        ...p,
        'memberIds': ['drafter-a'],
      });
      expect(
        (await call('drafter-a', 'POST', 'projects/$id/offline', {
          'confirmed': true,
        })).statusCode,
        200,
      );
      p = (await store.get('a', 'project', id))!;
      await call('admin-a', 'PATCH', 'projects/$id', {...p, 'memberIds': []});
      expect(
        (await call('drafter-a', 'POST', 'projects/$id/offline/upload', {
          ...upload,
          'userId': 'drafter-a',
          'version': 5,
        })).statusCode,
        404,
      );
    },
  );
  test(
    'scoped automation cannot approve; proposals require human CAS and audit',
    () async {
      final p = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Automation'}),
      );
      final id = p['id'];
      final other = await json(
        await call('admin-a', 'POST', 'projects', {'name': 'Unshared'}),
      );
      await call('admin-a', 'PUT', 'projects/$id/drawing', {
        'version': 1,
        'drawing': sampleDrawing('motor'),
      });
      final issue = {
        'confirmed': true,
        'label': 'Test model client',
        'projectIds': [id],
        'allowProposals': true,
      };
      expect(
        (await call('admin-a', 'POST', 'automation/tokens', {
          ...issue,
          'confirmed': false,
        })).statusCode,
        400,
      );
      final t = await json(
        await call('admin-a', 'POST', 'automation/tokens', issue),
      );
      tokens['scoped'] = t['token'];
      final list = await json(
        await call('scoped', 'GET', 'automation/projects'),
      );
      expect((list['projects'] as List).length, 1);
      expect(
        (await call(
          'scoped',
          'GET',
          'automation/projects/${other['id']}',
        )).statusCode,
        404,
      );
      expect((await call('scoped', 'GET', 'projects/$id')).statusCode, 401);
      expect(
        (await call('admin-a', 'GET', 'automation/projects')).statusCode,
        401,
      );
      expect(
        (await call('scoped', 'POST', 'projects/$id/releases', {
          'confirmed': true,
        })).statusCode,
        401,
      );
      final proposalBody = {
        'version': 2,
        'reason': 'Explicit proposal',
        'drawing': sampleDrawing('distribution'),
      };
      final v = await json(
        await call(
          'scoped',
          'POST',
          'automation/projects/$id/proposals',
          proposalBody,
        ),
      );
      expect((await store.get('a', 'project', id))!['version'], 2);
      final apply = 'automation/review/$id/${v['id']}/apply';
      expect(
        (await call('scoped', 'POST', apply, {
          'confirmed': true,
          'version': 2,
        })).statusCode,
        401,
      );
      expect(
        (await call('admin-b', 'POST', apply, {
          'confirmed': true,
          'version': 2,
        })).statusCode,
        404,
      );
      expect(
        (await call('admin-a', 'POST', apply, {'version': 2})).statusCode,
        400,
      );
      final responses = await Future.wait(
        List.generate(
          2,
          (_) =>
              call('admin-a', 'POST', apply, {'confirmed': true, 'version': 2}),
        ),
      );
      expect(responses.map((r) => r.statusCode).toList()..sort(), [200, 409]);
      final current = (await store.get('a', 'project', id))!;
      expect(current['activity']['proposalId'], v['id']);
      expect(current['activity']['confirmedBy'], 'admin-a');
      expect(current['release'], isNull);
      final review = await json(
        await call('admin-a', 'GET', 'automation/review/$id'),
      );
      expect(review['proposals'][0]['status'], 'applied');
      expect(
        (await call(
          'scoped',
          'POST',
          'automation/projects/$id/proposals',
          proposalBody,
        )).statusCode,
        409,
      );
      expect(
        (await call(
          'scoped',
          'GET',
          'automation/projects/$id/documents?version=2',
        )).statusCode,
        409,
      );
      expect(
        (await call(
          'scoped',
          'GET',
          'automation/projects/$id/documents?version=3',
        )).statusCode,
        200,
      );
      await call('admin-a', 'POST', 'automation/tokens/${t['id']}/revoke', {});
      expect(
        (await call('scoped', 'GET', 'automation/projects')).statusCode,
        401,
      );
      final ro = await json(
        await call('admin-a', 'POST', 'automation/tokens', {
          ...issue,
          'allowProposals': false,
        }),
      );
      tokens['readonly'] = ro['token'];
      expect(
        (await call('readonly', 'POST', 'automation/projects/$id/proposals', {
          ...proposalBody,
          'version': 3,
        })).statusCode,
        403,
      );
      await call('admin-a', 'PATCH', 'projects/$id', {
        ...current,
        'memberIds': ['drafter-a'],
      });
      final dt = await json(
        await call('drafter-a', 'POST', 'automation/tokens', issue),
      );
      tokens['drafter-api'] = dt['token'];
      expect(
        (await call(
          'drafter-api',
          'GET',
          'automation/projects/$id',
        )).statusCode,
        200,
      );
      var latest = (await store.get('a', 'project', id))!;
      await call('admin-a', 'PATCH', 'projects/$id', {
        ...latest,
        'memberIds': [],
      });
      expect(
        (await call(
          'drafter-api',
          'GET',
          'automation/projects/$id',
        )).statusCode,
        404,
      );
      await users.setUserActive(id: 'drafter-a', active: false);
      expect(
        (await call('drafter-api', 'GET', 'automation/projects')).statusCode,
        401,
      );
    },
  );
}
