import 'dart:convert';
import 'package:company_users_service/src/models.dart';
import 'package:company_users_service/src/repository_memory.dart';
import 'package:company_users_service/src/router.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  for (final role in ['admin', 'zeichner']) {
    test(
      '$role changes own password and invalidates every old session',
      () async {
        final repo = InMemoryCompanyUserRepository();
        await repo.createCompany(id: 'company-a', name: 'Firma A');
        final created = await repo.createUser(
          id: 'user-a',
          companyId: 'company-a',
          username: 'a',
          role: role == 'admin' ? UserRole.admin : UserRole.zeichner,
        );
        final router = CompanyUserRouter(
          repository: repo,
          internalToken: 'secret',
        ).handler;
        Future<Response> post(
          String path,
          Map<String, Object?> body, [
          String? token,
        ]) => router.call(
          Request(
            'POST',
            Uri.parse('http://localhost$path'),
            headers: token == null ? {} : {'authorization': 'Bearer $token'},
            body: jsonEncode(body),
          ),
        );
        Future<Response> get(String token) => router.call(
          Request(
            'GET',
            Uri.parse('http://localhost/me'),
            headers: {'authorization': 'Bearer $token'},
          ),
        );
        expect(
          (await post('/auth/activate', {
            'token': created.rawActivationToken,
            'password': 'old-password',
          })).statusCode,
          200,
        );
        Future<String> login(String password) async {
          final response = await post('/auth/login', {
            'username': 'a',
            'password': password,
          });
          expect(response.statusCode, 200);
          return (jsonDecode(await response.readAsString())
                  as Map<String, Object?>)['token']
              as String;
        }

        final first = await login('old-password');
        final second = await login('old-password');
        final changed = await post('/me/password', {
          'currentPassword': 'old-password',
          'newPassword': 'new-password-123',
          'confirmPassword': 'new-password-123',
        }, first);
        expect(changed.statusCode, 200);
        expect((await get(first)).statusCode, 401);
        expect((await get(second)).statusCode, 401);
        expect(
          (await post('/auth/login', {
            'username': 'a',
            'password': 'old-password',
          })).statusCode,
          401,
        );
        expect((await get(await login('new-password-123'))).statusCode, 200);
      },
    );
  }

  test(
    'missing authentication, incorrect password and invalid input do not change password',
    () async {
      final repo = InMemoryCompanyUserRepository();
      await repo.createCompany(id: 'c', name: 'C');
      final user = await repo.createUser(
        id: 'u',
        companyId: 'c',
        username: 'user',
        role: UserRole.admin,
      );
      final router = CompanyUserRouter(
        repository: repo,
        internalToken: 'secret',
      ).handler;
      Future<Response> post(
        String path,
        Map<String, Object?> body, [
        String? token,
      ]) => router.call(
        Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: token == null ? {} : {'authorization': 'Bearer $token'},
          body: jsonEncode(body),
        ),
      );
      await post('/auth/activate', {
        'token': user.rawActivationToken,
        'password': 'old-password',
      });
      final login = await post('/auth/login', {
        'username': 'user',
        'password': 'old-password',
      });
      final token =
          (jsonDecode(await login.readAsString())
                  as Map<String, Object?>)['token']
              as String;
      final valid = {
        'currentPassword': 'old-password',
        'newPassword': 'new-password-123',
        'confirmPassword': 'new-password-123',
      };
      expect((await post('/me/password', valid)).statusCode, 401);
      expect(
        (await post('/me/password', {
          ...valid,
          'currentPassword': 'wrong',
        }, token)).statusCode,
        403,
      );
      expect(
        (await post('/me/password', {
          ...valid,
          'confirmPassword': 'different',
        }, token)).statusCode,
        400,
      );
      expect(
        (await post('/me/password', {
          ...valid,
          'newPassword': 'short',
          'confirmPassword': 'short',
        }, token)).statusCode,
        400,
      );
      expect(
        (await post('/me/password', {
          ...valid,
          'newPassword': 123,
        }, token)).statusCode,
        400,
      );
      expect(
        (await post('/me/password', {
          ...valid,
          'newPassword': 'old-password',
          'confirmPassword': 'old-password',
        }, token)).statusCode,
        400,
      );
      expect(
        (await router.call(
          Request(
            'GET',
            Uri.parse('http://localhost/me'),
            headers: {'authorization': 'Bearer $token'},
          ),
        )).statusCode,
        200,
      );
    },
  );
}
