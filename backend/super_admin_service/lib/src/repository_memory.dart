import 'models.dart';
import 'repository.dart';

/// Reine In-Memory-Implementierung für `dart test` — keine Postgres-
/// Verbindung nötig (siehe `docs/architecture.md#testing`).
class InMemorySuperAdminRepository implements SuperAdminRepository {
  final List<SuperAdmin> _admins = [];
  final List<SuperAdminSession> _sessions = [];
  final List<AuditEntry> _audit = [];

  @override
  Future<bool> isEmpty() async => _admins.isEmpty;

  @override
  Future<SuperAdmin> createSuperAdmin({required String username, required String passwordHash}) async {
    final admin = SuperAdmin(
      id: 'super-admin-${_admins.length + 1}',
      username: username,
      passwordHash: passwordHash,
    );
    _admins.add(admin);
    return admin;
  }

  @override
  Future<SuperAdmin?> findByUsername(String username) async =>
      _admins.where((a) => a.username == username).firstOrNull;

  @override
  Future<SuperAdmin?> findById(String id) async => _admins.where((a) => a.id == id).firstOrNull;

  @override
  Future<void> saveSession(SuperAdminSession session) async {
    _sessions.removeWhere((s) => s.tokenHash == session.tokenHash);
    _sessions.add(session);
  }

  @override
  Future<SuperAdminSession?> findSession(String tokenHash) async =>
      _sessions.where((s) => s.tokenHash == tokenHash).firstOrNull;

  @override
  Future<void> deleteSession(String tokenHash) async {
    _sessions.removeWhere((s) => s.tokenHash == tokenHash);
  }

  @override
  Future<void> appendAudit(AuditEntry entry) async => _audit.add(entry);

  @override
  Future<List<AuditEntry>> listAudit() async => List.unmodifiable(_audit);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
