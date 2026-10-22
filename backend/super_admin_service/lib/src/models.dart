/// M1.1 Super-Admin-Backend — Datenmodelle. Bewusst von normalen
/// Firmen-Admins/Nutzern getrennt (eigener Dienst, eigene DB, eigene
/// Rolle) — siehe Roadmap: "Super-Admin-Identität und Audit von
/// Firmenanlage/Rollenvergabe klar von Firmen-Admins trennen".
class SuperAdmin {
  const SuperAdmin({required this.id, required this.username, required this.passwordHash});
  final String id;
  final String username;
  final String passwordHash;
}

class SuperAdminSession {
  const SuperAdminSession({
    required this.tokenHash,
    required this.superAdminId,
    required this.createdAt,
    required this.expiresAt,
  });
  final String tokenHash;
  final String superAdminId;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);
}

/// Nachvollziehbares Prüfen von Firmenanlage/Rollenvergabe (M1.1-
/// Vorgabe "Anlegen, Identifikation und nachvollziehbares Prüfen").
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.superAdminUsername,
    required this.action,
    required this.target,
    required this.createdAt,
  });
  final String id;
  final String superAdminUsername;
  final String action;
  final String target;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'superAdminUsername': superAdminUsername,
        'action': action,
        'target': target,
        'createdAt': createdAt.toIso8601String(),
      };
}
