import 'models.dart';

/// Repository-Schnittstelle (siehe `docs/architecture.md#testing`) —
/// `InMemorySuperAdminRepository` für Tests, `PostgresSuperAdminRepository`
/// für den echten Betrieb.
abstract class SuperAdminRepository {
  /// `true`, wenn noch kein Super-Admin existiert — steuert das
  /// Bootstrap-Anlegen aus Umgebungsvariablen beim Start.
  Future<bool> isEmpty();

  Future<SuperAdmin> createSuperAdmin({required String username, required String passwordHash});

  Future<SuperAdmin?> findByUsername(String username);

  Future<SuperAdmin?> findById(String id);

  Future<void> saveSession(SuperAdminSession session);

  Future<SuperAdminSession?> findSession(String tokenHash);

  Future<void> deleteSession(String tokenHash);

  Future<void> appendAudit(AuditEntry entry);

  Future<List<AuditEntry>> listAudit();
}
