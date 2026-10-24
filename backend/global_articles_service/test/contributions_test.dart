import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:global_articles_service/src/router.dart';
import 'package:test/test.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:global_articles_service/src/contributions/catalog.dart';
import 'package:global_articles_service/src/repository_memory.dart';

void main() {
  late ContributionCatalog c;
  const a = {'companyId': 'A', 'userId': 'alice', 'role': 'admin'};
  const b = {'companyId': 'B', 'userId': 'bob', 'role': 'admin'};
  Json draft({String source = 'userUpload'}) => {
    'action': 'create',
    'source': source,
    'rightsConfirmed': true,
    'payload': {
      'articleNumber': 'X1',
      'name': 'Public',
      'origin': 'Own design',
      'attribution': 'Test author',
      'license': 'CC-BY-4.0',
      'notes': 'PRIVATE',
      'ownerId': 'PRIVATE',
      'layers': {
        'electrical': {'voltageV': 0, 'private': 'SECRET'},
      },
    },
  };
  Json transition(Json d, String action) => {
    'action': action,
    'id': d['id'],
    'version': d['version'],
    'confirmed': true,
    'reason': 'Test reason',
    'actor': 'kay',
  };
  setUp(
    () => c = ContributionCatalog(MemoryRecords(), InMemoryArticleRepository()),
  );
  test(
    'encoded catalog IDs resolve through router and public history',
    () async {
      var d = await c.user(a, draft());
      d = await c.user(a, transition(d, 'submit'));
      d = await c.operator(transition(d, 'approve'));
      final router = ArticleRouter(
        repository: InMemoryArticleRepository(),
        catalog: c,
      ).handler;
      final path = Uri.encodeComponent(d['id'] as String);
      final response = await router.call(
        Request('GET', Uri.parse('http://localhost/articles/$path')),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString())['id'], d['id']);
      final history = await router.call(
        Request('GET', Uri.parse('http://localhost/articles/$path/history')),
      );
      expect(jsonDecode(await history.readAsString())['entries'].length, 1);
    },
  );
  test(
    'only explicit public fields survive; draft invisible; rights required',
    () async {
      await expectLater(
        c.user(a, {...draft(), 'rightsConfirmed': false}),
        throwsA(isA<ApiProblem>()),
      );
      final d = await c.user(a, draft());
      expect(d.toString(), isNot(contains('PRIVATE')));
      expect(d.toString(), isNot(contains('SECRET')));
      expect((d['payload'] as Json)['layers']['electrical']['voltageV'], 0);
      expect(await c.publicArticles(), isEmpty);
      await expectLater(
        c.user(b, transition(d, 'submit')),
        throwsA(isA<ApiProblem>()),
      );
    },
  );
  test(
    'publication, revision, reject, withdrawal retain immutable public history',
    () async {
      var d = await c.user(a, draft());
      d = await c.user(a, transition(d, 'submit'));
      await expectLater(
        c.user(a, {
          ...draft(),
          'action': 'edit',
          'id': d['id'],
          'version': d['version'],
          'reason': 'edit',
        }),
        throwsA(isA<ApiProblem>()),
      );
      d = await c.operator(transition(d, 'approve'));
      expect((await c.publicArticles()).length, 1);
      d = await c.user(a, {
        ...draft(),
        'action': 'edit',
        'id': d['id'],
        'version': d['version'],
        'reason': 'edit',
      });
      expect((await c.publicArticle(d['id']))!['version'], 1);
      d = await c.user(a, transition(d, 'submit'));
      d = await c.operator(transition(d, 'reject'));
      d = await c.user(a, transition(d, 'submit'));
      d = await c.operator(transition(d, 'approve'));
      expect((await c.publicArticle(d['id']))!['version'], 2);
      d = await c.user(a, transition(d, 'withdraw'));
      expect(await c.publicArticles(), isEmpty);
      final history = await c.publicHistory(d['id']);
      expect(history.length, 3);
      expect(history.toString(), isNot(contains('alice')));
    },
  );
  test(
    'manufacturer assignment only authorizes its own immutable area; revocation preserves provenance',
    () async {
      await expectLater(
        c.user(a, draft(source: 'manufacturer')),
        throwsA(isA<ApiProblem>()),
      );
      Json grant = {
        'action': 'manufacturer',
        'companyId': 'A',
        'name': 'Maker A',
        'active': true,
        'evidence': 'TEST evidence',
        'reason': 'Verified test identity',
        'confirmed': true,
        'version': 0,
        'actor': 'kay',
      };
      await c.operator(grant);
      await expectLater(c.user(a, draft()), throwsA(isA<ApiProblem>()));
      var d = await c.user(a, {
        ...draft(source: 'manufacturer'),
        'manufacturerName': 'Maker B',
      });
      expect(d['manufacturerName'], 'Maker A');
      await expectLater(
        c.user(b, draft(source: 'manufacturer')),
        throwsA(isA<ApiProblem>()),
      );
      d = await c.user(a, transition(d, 'submit'));
      d = await c.operator(transition(d, 'approve'));
      await c.operator({...grant, 'active': false, 'version': 1});
      expect((await c.publicArticle(d['id']))!['manufacturerName'], 'Maker A');
      d = await c.user(a, {
        ...draft(),
        'action': 'edit',
        'id': d['id'],
        'version': d['version'],
        'reason': 'edit',
      });
      expect(d['source'], 'manufacturer');
      await expectLater(
        c.user(a, transition(d, 'submit')),
        throwsA(isA<ApiProblem>()),
      );
    },
  );
  test(
    'stale changes and malformed data fail without changing records',
    () async {
      final d = await c.user(a, draft());
      await c.user(a, transition(d, 'submit'));
      await expectLater(
        c.user(a, transition(d, 'withdraw')),
        throwsA(isA<Conflict>()),
      );
      expect(
        (await c.user(a, {'action': 'list'}))['results'][0]['state'],
        'review',
      );
      await expectLater(
        c.operator({...transition(d, 'approve'), 'confirmed': false}),
        throwsA(isA<ApiProblem>()),
      );
    },
  );
}
