import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Dünner HTTP-Client für den Firmen-/Nutzerdienst (M1.3) — keine
/// Geschäftslogik, nur Anfragen bauen/Antworten parsen. Wirft
/// [ApiException] mit der Server-Fehlermeldung, damit die UI sie
/// direkt anzeigen kann statt generischer Fehler.
class ApiException implements Exception {
  ApiException(this.message, {required this.statusCode});
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

class CompanyUsersApi {
  CompanyUsersApi({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();
  final Uri baseUrl;
  final http.Client _http;

  Uri _endpoint(String path) =>
      Uri.parse('${baseUrl.toString().replaceFirst(RegExp(r"/+$"), "")}/$path');

  Map<String, String> _authHeaders(String token) => {
    'content-type': 'application/json',
    'authorization': 'Bearer $token',
  };

  Future<Map<String, Object?>> _parse(
    http.Response response, {
    int expect = 200,
  }) async {
    final body = response.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(response.body) as Map<String, Object?>;
    if (response.statusCode != expect) {
      throw ApiException(
        body['error'] as String? ??
            'Unerwarteter Serverfehler (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<Session> login({
    required String username,
    required String password,
  }) async {
    final response = await _http.post(
      _endpoint('auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = await _parse(response);
    return Session(
      token: body['token'] as String,
      username: body['username'] as String,
      role: userRoleFromWire(body['role'] as String),
      companyName: body['companyName'] as String,
      backendUrl: baseUrl,
    );
  }

  Future<void> activate({
    required String token,
    required String password,
  }) async {
    final response = await _http
        .post(
          _endpoint('auth/activate'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'token': token, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    await _parse(response);
  }

  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await _http
        .post(
          _endpoint('me/password'),
          headers: _authHeaders(token),
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
            'confirmPassword': confirmPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    await _parse(response);
  }

  Future<void> logout(String token) async {
    await _http.post(_endpoint('auth/logout'), headers: _authHeaders(token));
  }

  Future<List<CompanyUserListEntry>> listUsers(String token) async {
    final response = await _http.get(
      _endpoint('users'),
      headers: _authHeaders(token),
    );
    final body = await _parse(response);
    final raw = body['users'] as List;
    return raw
        .map((e) => CompanyUserListEntry.fromJson(e as Map<String, Object?>))
        .toList();
  }

  /// Gibt das Aktivierungstoken zurück — in M1 gibt es noch keinen
  /// Versandweg (siehe `docs/architecture.md`), der Admin muss es dem
  /// neuen Zeichner selbst mitteilen.
  Future<String> createZeichner(
    String token, {
    required String username,
  }) async {
    final response = await _http.post(
      _endpoint('users'),
      headers: _authHeaders(token),
      body: jsonEncode({'username': username}),
    );
    final body = await _parse(response, expect: 201);
    return body['activationToken'] as String;
  }

  Future<void> setUserActive(
    String token, {
    required String userId,
    required bool active,
  }) async {
    final response = await _http.patch(
      _endpoint('users/$userId'),
      headers: _authHeaders(token),
      body: jsonEncode({'active': active}),
    );
    await _parse(response);
  }
}
