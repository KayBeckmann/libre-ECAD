/// M1.4 — nur zwei Rollen (siehe Firmen-/Nutzerdienst, M1.3).
enum UserRole { admin, zeichner }

UserRole userRoleFromWire(String value) => switch (value) {
  'admin' => UserRole.admin,
  'zeichner' => UserRole.zeichner,
  _ => throw ArgumentError('Unbekannte Rolle: $value'),
};

/// Angemeldete Sitzung — bewusst nur im Speicher gehalten (siehe
/// `docs/architecture.md`), geht bei App-Neustart verloren.
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.role,
    required this.companyName,
    required this.backendUrl,
  });

  final String token;
  final String username;
  final UserRole role;
  final String companyName;
  final Uri backendUrl;
}

class CompanyUserListEntry {
  const CompanyUserListEntry({
    required this.id,
    required this.username,
    required this.role,
    required this.active,
    required this.activated,
  });
  final String id;
  final String username;
  final UserRole role;
  final bool active;
  final bool activated;

  factory CompanyUserListEntry.fromJson(Map<String, Object?> json) =>
      CompanyUserListEntry(
        id: json['id'] as String,
        username: json['username'] as String,
        role: userRoleFromWire(json['role'] as String),
        active: json['active'] as bool,
        activated: json['activated'] as bool,
      );
}

class GlobalArticleSearchHit {
  const GlobalArticleSearchHit({
    required this.id,
    required this.version,
    required this.articleNumber,
    required this.name,
    required this.source,
    this.manufacturerName,
  });
  final String id;
  final int version;
  final String articleNumber;
  final String name;
  final String source;
  final String? manufacturerName;

  factory GlobalArticleSearchHit.fromJson(Map<String, Object?> json) =>
      GlobalArticleSearchHit(
        id: json['id'] as String,
        version: json['version'] as int,
        articleNumber: json['articleNumber'] as String,
        name: json['name'] as String,
        source: json['source'] as String,
        manufacturerName: json['manufacturerName'] as String?,
      );
}
