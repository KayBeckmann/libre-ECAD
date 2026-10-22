import 'package:postgres/postgres.dart';
import 'package:shared_server_kit/shared_server_kit.dart';

import 'models.dart';
import 'repository.dart';

class PostgresCompanyUserRepository implements CompanyUserRepository {
  PostgresCompanyUserRepository(this._db);
  final Connection _db;

  @override
  Future<Company> createCompany({required String id, required String name}) async {
    await _db.execute(
      Sql.named('INSERT INTO companies (id, name) VALUES (@id, @name)'),
      parameters: {'id': id, 'name': name},
    );
    return Company(id: id, name: name, active: true);
  }

  @override
  Future<Company?> findCompanyById(String id) async {
    final result = await _db.execute(
      Sql.named('SELECT id, name, active FROM companies WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return Company(id: row[0] as String, name: row[1] as String, active: row[2] as bool);
  }

  @override
  Future<({AppUser user, String rawActivationToken})> createUser({
    required String id,
    required String companyId,
    required String username,
    required UserRole role,
  }) async {
    await _db.execute(
      Sql.named('''
        INSERT INTO users (id, company_id, username, role)
        VALUES (@id, @companyId, @username, @role)
      '''),
      parameters: {'id': id, 'companyId': companyId, 'username': username, 'role': role.wireValue},
    );
    final rawToken = SessionTokens.generate();
    await _db.execute(
      Sql.named('''
        INSERT INTO activation_tokens (token_hash, user_id, expires_at)
        VALUES (@tokenHash, @userId, @expiresAt)
      '''),
      parameters: {
        'tokenHash': SessionTokens.hashOf(rawToken),
        'userId': id,
        'expiresAt': DateTime.now().toUtc().add(const Duration(days: 7)),
      },
    );
    final user = AppUser(id: id, companyId: companyId, username: username, role: role, active: true);
    return (user: user, rawActivationToken: rawToken);
  }

  @override
  Future<AppUser?> findUserByUsername(String username) async {
    final result = await _db.execute(
      Sql.named(
        'SELECT id, company_id, username, password_hash, role, active FROM users WHERE username = @username',
      ),
      parameters: {'username': username},
    );
    if (result.isEmpty) return null;
    return _toUser(result.first);
  }

  @override
  Future<AppUser?> findUserById(String id) async {
    final result = await _db.execute(
      Sql.named('SELECT id, company_id, username, password_hash, role, active FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _toUser(result.first);
  }

  @override
  Future<List<AppUser>> listUsersForCompany(String companyId) async {
    final result = await _db.execute(
      Sql.named(
        'SELECT id, company_id, username, password_hash, role, active FROM users '
        'WHERE company_id = @companyId ORDER BY username',
      ),
      parameters: {'companyId': companyId},
    );
    return [for (final row in result) _toUser(row)];
  }

  @override
  Future<int> countActiveActivatedAdmins(String companyId) async {
    final result = await _db.execute(
      Sql.named('''
        SELECT count(*) FROM users
        WHERE company_id = @companyId AND role = 'admin' AND active = true AND password_hash IS NOT NULL
      '''),
      parameters: {'companyId': companyId},
    );
    return result.first.first as int;
  }

  @override
  Future<bool> setUserActive({required String id, required bool active}) async {
    final result = await _db.execute(
      Sql.named('UPDATE users SET active = @active WHERE id = @id'),
      parameters: {'active': active, 'id': id},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<bool> activateWithToken({required String rawToken, required String passwordHash}) async {
    final tokenHash = SessionTokens.hashOf(rawToken);
    final tokenResult = await _db.execute(
      Sql.named(
        'SELECT user_id, expires_at, used_at FROM activation_tokens WHERE token_hash = @tokenHash',
      ),
      parameters: {'tokenHash': tokenHash},
    );
    if (tokenResult.isEmpty) return false;
    final row = tokenResult.first;
    final expiresAt = row[1] as DateTime;
    final usedAt = row[2] as DateTime?;
    final now = DateTime.now().toUtc();
    if (usedAt != null || now.isAfter(expiresAt)) return false;

    final userId = row[0] as String;
    await _db.execute(
      Sql.named('UPDATE users SET password_hash = @hash WHERE id = @id'),
      parameters: {'hash': passwordHash, 'id': userId},
    );
    await _db.execute(
      Sql.named('UPDATE activation_tokens SET used_at = @now WHERE token_hash = @tokenHash'),
      parameters: {'now': now, 'tokenHash': tokenHash},
    );
    return true;
  }

  @override
  Future<void> saveSession(UserSession session) async {
    await _db.execute(
      Sql.named('''
        INSERT INTO user_sessions (token_hash, user_id, company_id, created_at, expires_at)
        VALUES (@tokenHash, @userId, @companyId, @createdAt, @expiresAt)
        ON CONFLICT (token_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at
      '''),
      parameters: {
        'tokenHash': session.tokenHash,
        'userId': session.userId,
        'companyId': session.companyId,
        'createdAt': session.createdAt,
        'expiresAt': session.expiresAt,
      },
    );
  }

  @override
  Future<UserSession?> findSession(String tokenHash) async {
    final result = await _db.execute(
      Sql.named(
        'SELECT token_hash, user_id, company_id, created_at, expires_at FROM user_sessions '
        'WHERE token_hash = @tokenHash',
      ),
      parameters: {'tokenHash': tokenHash},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return UserSession(
      tokenHash: row[0] as String,
      userId: row[1] as String,
      companyId: row[2] as String,
      createdAt: row[3] as DateTime,
      expiresAt: row[4] as DateTime,
    );
  }

  @override
  Future<void> deleteSession(String tokenHash) async {
    await _db.execute(
      Sql.named('DELETE FROM user_sessions WHERE token_hash = @tokenHash'),
      parameters: {'tokenHash': tokenHash},
    );
  }

  AppUser _toUser(ResultRow row) => AppUser(
        id: row[0] as String,
        companyId: row[1] as String,
        username: row[2] as String,
        passwordHash: row[3] as String?,
        role: UserRoleJson.fromWire(row[4] as String),
        active: row[5] as bool,
      );
}
