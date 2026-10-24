import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'company_users_api.dart';

class WorkspaceApi {
  WorkspaceApi(this.session, {http.Client? client})
    : _http = client ?? http.Client();
  final Session session;
  final http.Client _http;
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final base = session.backendUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    final request = http.Request(method, Uri.parse('$base/api/v1/$path'));
    request.headers.addAll({
      'authorization': 'Bearer ${session.token}',
      'content-type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 15)),
    );
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        value['error'] as String? ?? 'Anfrage fehlgeschlagen.',
        statusCode: response.statusCode,
      );
    }
    return value;
  }

  void close() => _http.close();
}
