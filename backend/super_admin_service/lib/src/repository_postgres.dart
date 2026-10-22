import 'package:postgres/postgres.dart';

import 'models.dart';
import 'repository.dart';

class PostgresSuperAdminRepository implements SuperAdminRepository {
  PostgresSuperAdminRepository(this._db);
  final Connection _db;

  @override
  Future<bool> isEmpty() async {
    final result = await _db.execute('SELECT count(*) FROM super_admins');
    return (result.first.first as int) == 0;
  }

  @override
  Future<SuperAdmin> createSuperAdmin({required String username, required String passwordHash}) async {
    final id = 'super-admin-${DateTime.now().microsecondsSinceEpoch}';
    await _db.execute(
      Sql.named(
        'INSERT INTO super_admins (id, username, password_hash) VALUES (@id, @username, @hash)',
      ),
      parameters: {'id': id, 'username': username, 'hash': passwordHash},
    );
    return SuperAdmin(id: id, username: username, passwordHash: passwordHash);
  }

  @override
  Future<SuperAdmin?> findByUsername(String username) async {
    final result = await _db.execute(
      Sql.named('SELECT id, username, password_hash FROM super_admins WHERE username = @username'),
      parameters: {'username': username},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return SuperAdmin(id: row[0] as String, username: row[1] as String, passwordHash: row[2] as String);
  }

  @override
  Future<SuperAdmin?> findById(String id) async {
    final result = await _db.execute(
      Sql.named('SELECT id, username, password_hash FROM super_admins WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return SuperAdmin(id: row[0] as String, username: row[1] as String, passwordHash: row[2] as String);
  }

  @override
  Future<void> saveSession(SuperAdminSession session) async {
    await _db.execute(
      Sql.named('''
        INSERT INTO super_admin_sessions (token_hash, super_admin_id, created_at, expires_at)
        VALUES (@tokenHash, @adminId, @createdAt, @expiresAt)
        ON CONFLICT (token_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at
      '''),
      parameters: {
        'tokenHash': session.tokenHash,
        'adminId': session.superAdminId,
        'createdAt': session.createdAt,
        'expiresAt': session.expiresAt,
      },
    );
  }

  @override
  Future<SuperAdminSession?> findSession(String tokenHash) async {
    final result = await _db.execute(
      Sql.named(
        'SELECT token_hash, super_admin_id, created_at, expires_at FROM super_admin_sessions '
        'WHERE token_hash = @tokenHash',
      ),
      parameters: {'tokenHash': tokenHash},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return SuperAdminSession(
      tokenHash: row[0] as String,
      superAdminId: row[1] as String,
      createdAt: row[2] as DateTime,
      expiresAt: row[3] as DateTime,
    );
  }

  @override
  Future<void> deleteSession(String tokenHash) async {
    await _db.execute(
      Sql.named('DELETE FROM super_admin_sessions WHERE token_hash = @tokenHash'),
      parameters: {'tokenHash': tokenHash},
    );
  }

  @override
  Future<void> appendAudit(AuditEntry entry) async {
    await _db.execute(
      Sql.named('''
        INSERT INTO audit_log (id, super_admin_username, action, target, created_at)
        VALUES (@id, @username, @action, @target, @createdAt)
      '''),
      parameters: {
        'id': entry.id,
        'username': entry.superAdminUsername,
        'action': entry.action,
        'target': entry.target,
        'createdAt': entry.createdAt,
      },
    );
  }

  @override
  Future<List<AuditEntry>> listAudit() async {
    final result = await _db.execute(
      'SELECT id, super_admin_username, action, target, created_at FROM audit_log ORDER BY created_at DESC',
    );
    return [
      for (final row in result)
        AuditEntry(
          id: row[0] as String,
          superAdminUsername: row[1] as String,
          action: row[2] as String,
          target: row[3] as String,
          createdAt: row[4] as DateTime,
        ),
    ];
  }
}
