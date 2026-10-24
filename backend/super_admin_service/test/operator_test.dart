import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:super_admin_service/src/operator/console.dart';

void main() {
  late OperatorConsole console;
  late List<Json> calls;
  setUp(() {
    calls = [];
    final client = MockClient((r) async {
      expect(r.headers['X-Internal-Token'], 'internal');
      final b = jsonDecode(r.body) as Json;
      calls.add(b);
      if (r.url.host == 'companies' && b['action'] == 'list')
        return http.Response(
          jsonEncode({
            'companies': [
              {'id': 'A', 'mode': 'managed', 'active': true},
            ],
          }),
          200,
        );
      return http.Response(jsonEncode(b), 200);
    });
    console = OperatorConsole(
      records: MemoryRecords(),
      companies: InternalApi(
        Uri.parse('http://companies'),
        'internal',
        client: client,
      ),
      catalog: InternalApi(
        Uri.parse('http://catalog'),
        'internal',
        client: client,
      ),
    );
  });
  Json payment(String id) => {
    'action': 'payment',
    'id': id,
    'companyId': 'A',
    'status': 'open',
    'amountMinor': 1900,
    'currency': 'EUR',
    'date': '2026-10-24',
    'reference': 'TEST-INVOICE-1',
    'reason': 'Synthetischer Testbeleg',
    'confirmed': true,
  };
  test(
    'manual payments are immutable, auditable, corrected only once per revision',
    () async {
      final p = await console.execute('kay', payment('p1'));
      expect(p['actor'], 'kay');
      await expectLater(
        console.execute('kay', payment('p1')),
        throwsA(isA<Conflict>()),
      );
      await console.execute('kay', {
        ...payment('p2'),
        'status': 'success',
        'corrects': 'p1',
      });
      await expectLater(
        console.execute('kay', {...payment('p3'), 'corrects': 'p1'}),
        throwsA(isA<ApiProblem>()),
      );
      final d = await console.execute('kay', {'action': 'overview'});
      expect((d['payments'] as List).length, 2);
      expect(d['payments'][0]['status'], 'open');
      expect(d['payments'][1]['status'], 'success');
    },
  );
  test(
    'references, confirmations, valid amounts and dates are mandatory',
    () async {
      for (final change in [
        {'confirmed': false},
        {'reference': ''},
        {'amountMinor': -1},
        {'amountMinor': 1.2},
        {'date': '2026-02-30'},
        {'status': 'paid-maybe'},
      ]) {
        await expectLater(
          console.execute('kay', {...payment('p1'), ...change}),
          throwsA(isA<ApiProblem>()),
        );
      }
      expect(
        (await console.execute('kay', {'action': 'overview'}))['payments'],
        isEmpty,
      );
    },
  );
  test(
    'external registration performs no network call and is never billed or assigned locally',
    () async {
      final d = await console.execute('kay', {
        'action': 'external',
        'id': 'external-demo',
        'name': 'Provider firm',
        'url': 'https://backend.example.test',
        'provider': 'Provider',
        'version': 0,
        'confirmed': true,
        'reason': 'TEST',
      });
      expect(d['mode'], 'external');
      expect(calls, isEmpty);
      await expectLater(
        console.execute('kay', {
          ...payment('p1'),
          'companyId': 'external-demo',
        }),
        throwsA(isA<ApiProblem>()),
      );
      await expectLater(
        console.execute('kay', {
          'action': 'catalog',
          'operation': 'manufacturer',
          'companyId': 'external-demo',
        }),
        throwsA(isA<ApiProblem>()),
      );
    },
  );
  test(
    'operator identity cannot be spoofed and unknown forwarding operations fail',
    () async {
      final result = await console.execute('kay', {
        'action': 'catalog',
        'operation': 'list',
        'actor': 'attacker',
        'mode': 'user',
      });
      expect(result['actor'], 'kay');
      expect(result['mode'], 'operator');
      await expectLater(
        console.execute('kay', {
          'action': 'managed',
          'operation': 'dropDatabase',
        }),
        throwsA(isA<ApiProblem>()),
      );
    },
  );
  test('contracts use compare-and-swap and retain history', () async {
    final body = {
      'action': 'contract',
      'companyId': 'A',
      'status': 'trial',
      'reference': 'TEST-TRIAL',
      'confirmed': true,
      'reason': 'Test',
      'version': 0,
    };
    await console.execute('kay', body);
    await expectLater(console.execute('kay', body), throwsA(isA<Conflict>()));
    await console.execute('kay', {...body, 'version': 1, 'status': 'active'});
    final d = await console.execute('kay', {
      'action': 'history',
      'kind': 'contract',
      'id': 'A',
    });
    expect((d['entries'] as List).length, 2);
    expect(d['entries'][0]['status'], 'trial');
  });
}
