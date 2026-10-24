import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libre_ecad_app/src/api/company_users_api.dart';
import 'package:libre_ecad_app/src/api/global_articles_api.dart';
import 'package:libre_ecad_app/src/api/workspace_api.dart';
import 'package:libre_ecad_app/src/models.dart';

void main() {
  test(
    'LAN proxy prefixes survive authentication, workspace and catalog requests',
    () async {
      final client = MockClient((r) async {
        if (r.url.path == '/api/company/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'test-token',
              'username': 'test',
              'role': 'admin',
              'companyName': 'Test',
            }),
            200,
          );
        }
        if (r.url.path == '/api/company/api/v1/projects') {
          expect(r.headers['authorization'], 'Bearer test-token');
          return http.Response('{"projects":[]}', 200);
        }
        if (r.url.path == '/api/global/articles') {
          expect(r.url.queryParameters, {
            'query': 'B16 & Klemme',
            'source': 'manufacturer',
            'manufacturer': 'ACME',
          });
          return http.Response('{"results":[]}', 200);
        }
        fail('Unexpected URL: ${r.url}');
      });
      final session = await CompanyUsersApi(
        baseUrl: Uri.parse('http://lan.test:8185/api/company'),
        httpClient: client,
      ).login(username: 'test', password: 'test');
      expect(session.role, UserRole.admin);
      await WorkspaceApi(session, client: client).request('GET', 'projects');
      await GlobalArticlesApi(
        baseUrl: Uri.parse('http://lan.test:8185/api/global/'),
        httpClient: client,
      ).search('B16 & Klemme', source: 'manufacturer', manufacturer: 'ACME');
    },
  );
  test(
    'version conflicts expose server message without implicit retry',
    () async {
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        return http.Response('{"error":"Konflikt: neu laden"}', 409);
      });
      final api = WorkspaceApi(
        Session(
          token: 't',
          username: 'test',
          role: UserRole.admin,
          companyName: 'Test',
          backendUrl: Uri.parse('http://test/'),
        ),
        client: client,
      );
      await expectLater(
        api.request('PATCH', 'articles/test', {'version': 1}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      expect(requests, 1);
    },
  );
}
