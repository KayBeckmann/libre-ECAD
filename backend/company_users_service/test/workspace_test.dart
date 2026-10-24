import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
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
}
