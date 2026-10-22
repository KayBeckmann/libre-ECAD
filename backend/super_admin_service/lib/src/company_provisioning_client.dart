import 'dart:convert';
import 'package:http/http.dart' as http;

/// M1.1 ruft M1.3 (Firmen-/Nutzerdienst) auf, statt Firmen-/Nutzer-
/// Daten selbst zu halten — jeder Dienst bleibt für seine eigenen
/// Daten zuständig (siehe `docs/architecture.md`). Der Aufruf läuft
/// über einen separaten `/internal/*`-Pfad, geschützt durch ein
/// gemeinsames Secret (`X-Internal-Token`), **nicht** über die
/// öffentlichen `/auth`-Endpunkte des Firmen-/Nutzerdienstes.
abstract class CompanyProvisioningClient {
  /// Wirft [CompanyProvisioningException] bei jedem Fehler (Dienst
  /// nicht erreichbar, abgelehnt, Namenskonflikt) — der Aufrufer
  /// (Router) entscheidet, ob/wie das dem Super-Admin gemeldet wird.
  Future<ProvisionedCompany> createCompany({required String name});

  Future<ProvisionedAdmin> createFirstAdmin({required String companyId, required String username});
}

class ProvisionedCompany {
  const ProvisionedCompany({required this.companyId, required this.name});
  final String companyId;
  final String name;
}

class ProvisionedAdmin {
  const ProvisionedAdmin({
    required this.userId,
    required this.username,
    required this.activationToken,
  });
  final String userId;
  final String username;

  /// Einmaliges Aktivierungstoken (siehe `docs/architecture.md` —
  /// "offene, bewusst vertagte Punkte": kein SMTP-Versand in M1, Kay
  /// gibt diesen Wert dem Firmen-Admin selbst weiter).
  final String activationToken;
}

class CompanyProvisioningException implements Exception {
  CompanyProvisioningException(this.message);
  final String message;
  @override
  String toString() => 'CompanyProvisioningException: $message';
}

class HttpCompanyProvisioningClient implements CompanyProvisioningClient {
  HttpCompanyProvisioningClient({
    required this.baseUrl,
    required this.internalToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final String internalToken;
  final http.Client _http;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'X-Internal-Token': internalToken,
      };

  @override
  Future<ProvisionedCompany> createCompany({required String name}) async {
    final response = await _http.post(
      baseUrl.resolve('/internal/companies'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 201) {
      throw CompanyProvisioningException(
        'Firmen-/Nutzerdienst lehnte Firmenanlage ab (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return ProvisionedCompany(companyId: json['companyId'] as String, name: json['name'] as String);
  }

  @override
  Future<ProvisionedAdmin> createFirstAdmin({
    required String companyId,
    required String username,
  }) async {
    final response = await _http.post(
      baseUrl.resolve('/internal/companies/$companyId/admins'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    if (response.statusCode != 201) {
      throw CompanyProvisioningException(
        'Firmen-/Nutzerdienst lehnte Admin-Anlage ab (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return ProvisionedAdmin(
      userId: json['userId'] as String,
      username: json['username'] as String,
      activationToken: json['activationToken'] as String,
    );
  }
}
