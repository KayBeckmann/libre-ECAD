import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'records.dart';
import 'responses.dart';

class ApiProblem implements Exception {
  ApiProblem(this.status, this.message);
  final int status;
  final String message;
}

String requiredText(Json body, String key, {int max = 200}) {
  final v = body[key];
  if (v is! String || v.trim().isEmpty || v.length > max)
    throw ApiProblem(400, '$key: Text erforderlich, maximal $max Zeichen.');
  return v.trim();
}

int expectedVersion(Json body) {
  final v = body['version'];
  if (v is! int || v < 0) throw ApiProblem(400, 'Versionsnummer erforderlich.');
  return v;
}

void confirmed(Json body) {
  if (body['confirmed'] != true)
    throw ApiProblem(400, 'Bewusste Bestätigung erforderlich.');
}

Future<Json> readJson(Request request, {int maxBytes = 131072}) async {
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) throw ApiProblem(413, 'Anfrage zu groß.');
  }
  final body = jsonDecode(utf8.decode(bytes));
  if (body is! Json) throw ApiProblem(400, 'JSON-Objekt erforderlich.');
  return body;
}

Future<Response> apiGuard(Future<Response> Function() action) async {
  try {
    return await action();
  } on ApiProblem catch (e) {
    return jsonError(e.message, status: e.status);
  } on Conflict {
    return jsonError(
      'Zwischenzeitlich geändert. Neu laden und erneut entscheiden.',
      status: 409,
    );
  } on FormatException {
    return jsonError('Ungültige Eingabe.', status: 400);
  }
}

class InternalApi {
  InternalApi(this.base, this.token, {http.Client? client})
    : client = client ?? http.Client();
  final Uri base;
  final String token;
  final http.Client client;
  Future<Json> call(String path, {String method = 'GET', Json? body}) async {
    if (token.isEmpty)
      throw ApiProblem(503, 'Dienstverbindung nicht konfiguriert.');
    try {
      final request = http.Request(method, base.resolve(path));
      request.headers.addAll({
        'X-Internal-Token': token,
        'Content-Type': 'application/json',
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Json;
      if (response.statusCode >= 400)
        throw ApiProblem(
          response.statusCode,
          data['error']?.toString() ?? 'Dienstfehler',
        );
      return data;
    } on ApiProblem {
      rethrow;
    } catch (_) {
      throw ApiProblem(
        503,
        'Verbundener Dienst nicht erreichbar. Nicht ungeprüft wiederholen; zunächst neu laden.',
      );
    }
  }
}
