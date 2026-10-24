import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store.dart';

class GlobalCatalogUnavailable implements Exception {}

class GlobalCatalog {
  GlobalCatalog(this.baseUrl);
  final Uri baseUrl;
  Future<Document?> find(String id) async {
    final client = http.Client();
    try {
      final response = await client
          .get(baseUrl.resolve('/articles/${Uri.encodeComponent(id)}'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) throw GlobalCatalogUnavailable();
      return jsonDecode(response.body) as Document;
    } catch (_) {
      throw GlobalCatalogUnavailable();
    } finally {
      client.close();
    }
  }
}
