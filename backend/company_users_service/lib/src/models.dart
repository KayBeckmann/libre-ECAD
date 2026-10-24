/// M1.3 — nur zwei Rollen (Roadmap: "Nur zwei Rollen: Admin (Nutzer
/// der eigenen Firma verwalten) und Zeichner (sich anmelden; kein
/// Administrationsrecht)"). Weitere Rollen/Rechte sind spätere
/// Meilensteine.
enum UserRole { admin, zeichner }

extension UserRoleJson on UserRole {
  String get wireValue => switch (this) {
    UserRole.admin => 'admin',
    UserRole.zeichner => 'zeichner',
  };

  static UserRole fromWire(String value) => switch (value) {
    'admin' => UserRole.admin,
    'zeichner' => UserRole.zeichner,
    _ => throw ArgumentError('Unbekannte UserRole: $value'),
  };
}

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.active,
    this.authEpoch = 0,
  });
  final String id;
  final String name;
  final bool active;
  final int authEpoch;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.companyId,
    required this.username,
    required this.role,
    required this.active,
    this.passwordHash,
    this.authEpoch = 0,
  });
  final String id;
  final String companyId;
  final String username;
  final UserRole role;
  final bool active;
  final int authEpoch;

  /// `null`, solange der Erstzugang noch nicht aktiviert wurde (siehe
  /// `docs/architecture.md`: kein Passwort wird je per Dokument/Log
  /// übertragen — der Nutzer setzt es selbst über das
  /// Aktivierungstoken).
  final String? passwordHash;

  bool get isActivated => passwordHash != null;
}

class UserSession {
  const UserSession({
    required this.tokenHash,
    required this.userId,
    required this.companyId,
    required this.createdAt,
    required this.expiresAt,
    this.companyEpoch = 0,
    this.userEpoch = 0,
  });
  final String tokenHash;
  final String userId;
  final String companyId;
  final int companyEpoch, userEpoch;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);
}

class ActivationToken {
  const ActivationToken({
    required this.tokenHash,
    required this.userId,
    required this.expiresAt,
    required this.usedAt,
  });
  final String tokenHash;
  final String userId;
  final DateTime expiresAt;
  final DateTime? usedAt;

  bool isValid(DateTime now) => usedAt == null && now.isBefore(expiresAt);
}
