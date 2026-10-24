import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Demo-Client für den globalen Artikel-Dienst (M1.2) — M1.4 soll
/// nur zeigen, dass der separate Dienst erreichbar ist (Roadmap),
/// kein vollwertiger Artikel-/Projekteditor.
class GlobalArticlesApi {
  GlobalArticlesApi({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();
  final Uri baseUrl;
  final http.Client _http;

  Uri _endpoint(String path) => Uri.parse(
      '${baseUrl.toString().replaceFirst(RegExp(r"/+$"), "")}/$path');

  Future<List<GlobalArticleSearchHit>> search(String query) async {
    final response =
        await _http.get(_endpoint('articles?query=${Uri.encodeQueryComponent(query)}'));
    if (response.statusCode != 200) {
      throw Exception('Globaler Artikel-Dienst nicht erreichbar (HTTP ${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final raw = body['results'] as List;
    return raw.map((e) => GlobalArticleSearchHit.fromJson(e as Map<String, Object?>)).toList();
  }
}
