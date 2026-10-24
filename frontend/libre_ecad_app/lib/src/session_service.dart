import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api/company_users_api.dart';
import 'api/global_articles_api.dart';
import 'models.dart';

/// Kays Managed-Backend ist vorbelegt, aber änderbar (Roadmap M1.4) —
/// für die lokale Entwicklung/Docker-Compose-Vorschau zeigt dieser
/// Platzhalter auf den lokalen `company-users-service`. **Vor echtem
/// Managed-Betrieb durch die reale Domain ersetzen.**
final defaultManagedBackendUrl = kIsWeb
    ? Uri.base.resolve('/api/company/').toString()
    : 'http://localhost:8183/';

/// M1 hat noch keine Service-Discovery zwischen Frontend und dem
/// globalen Artikel-Dienst — der wird separat konfiguriert (gleicher
/// Platzhalter-Charakter wie [defaultManagedBackendUrl]).
final defaultGlobalArticlesUrl = kIsWeb
    ? Uri.base.resolve('/api/global/').toString()
    : 'http://localhost:8182/';

const _prefsBackendUrlKey = 'libre_ecad.backend_url';
const _prefsArticlesUrlKey = 'libre_ecad.global_articles_url';

/// Hält die aktuelle Sitzung und die gewählte Backend-URL. Bewusst
/// **kein** persistenter Session-Token (siehe `docs/architecture.md`)
/// — ein Neustart der App verlangt erneute Anmeldung; das ist für M1
/// ausreichend und vermeidet, ein Sicherheitskonzept für den
/// Geräte-Speicher vorwegzunehmen, bevor Offline-Arbeit (M6) entschieden ist.
///
/// [httpClient] ist injizierbar (Default: ein echter `http.Client`) —
/// Widget-Tests übergeben hier ein `MockClient`, weil `flutter_test`
/// echte Netzwerkaufrufe grundsätzlich blockiert (bekannte
/// Plattformgrenze, kein Produktionsbug). Alle vom Frontend erzeugten
/// API-Clients teilen sich dasselbe `httpClient`, siehe
/// [companyUsersApiFor]/[globalArticlesApiFor].
class SessionService extends ChangeNotifier {
  SessionService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Session? _session;
  Session? get session => _session;
  bool get isLoggedIn => _session != null;

  CompanyUsersApi companyUsersApiFor(Uri baseUrl) =>
      CompanyUsersApi(baseUrl: baseUrl, httpClient: _httpClient);

  GlobalArticlesApi globalArticlesApiFor(Uri baseUrl) =>
      GlobalArticlesApi(baseUrl: baseUrl, httpClient: _httpClient);

  Future<String> loadBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsBackendUrlKey) ?? defaultManagedBackendUrl;
  }

  Future<void> saveBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBackendUrlKey, url);
  }

  Future<String> loadGlobalArticlesUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsArticlesUrlKey) ?? defaultGlobalArticlesUrl;
  }

  Future<void> saveGlobalArticlesUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsArticlesUrlKey, url);
  }

  Future<void> login({required String backendUrl, required String username, required String password}) async {
    final api = companyUsersApiFor(Uri.parse(backendUrl));
    _session = await api.login(username: username, password: password);
    await saveBackendUrl(backendUrl);
    notifyListeners();
  }

  Future<void> logout() async {
    final current = _session;
    if (current != null) {
      // Sitzung beim Backend-Wechsel/Abmelden sicher trennen (Roadmap
      // M1.4) — serverseitig widerrufen, nicht nur lokal vergessen.
      await companyUsersApiFor(current.backendUrl).logout(current.token);
    }
    _session = null;
    notifyListeners();
  }
}
