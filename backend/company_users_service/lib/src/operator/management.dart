import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:shelf/shelf.dart';

Future<void> migrateManagement(Connection db) async {
  await db.runTx((tx) async {
    await tx.execute('SELECT pg_advisory_xact_lock(28471824)');
    await tx.execute(
      'ALTER TABLE companies ADD COLUMN IF NOT EXISTS management_version INTEGER NOT NULL DEFAULT 1',
    );
    await tx.execute(
      'ALTER TABLE companies ADD COLUMN IF NOT EXISTS auth_epoch INTEGER NOT NULL DEFAULT 0',
    );
    await tx.execute(
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_epoch INTEGER NOT NULL DEFAULT 0',
    );
    await tx.execute(
      'ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS company_epoch INTEGER NOT NULL DEFAULT 0',
    );
    await tx.execute(
      'ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS user_epoch INTEGER NOT NULL DEFAULT 0',
    );
    await tx.execute('''CREATE TABLE IF NOT EXISTS management_audit (
      id TEXT PRIMARY KEY,company_id TEXT NOT NULL REFERENCES companies(id),
      actor TEXT NOT NULL, action TEXT NOT NULL, reason TEXT NOT NULL, details JSONB NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now())''');
  });
}

/// The same lock is used by normal account changes and activation in the repository.
Future<bool> safeUserActive(TxSession tx, String id, bool active) async {
  final rows = await tx.execute(
    Sql.named(
      'SELECT company_id,role,active,password_hash FROM users WHERE id=@id',
    ),
    parameters: {'id': id},
  );
  if (rows.isEmpty) return false;
  final row = rows.first;
  if (!active && row[1] == 'admin' && row[2] == true && row[3] != null) {
    final count = await tx.execute(
      Sql.named(
        "SELECT count(*) FROM users WHERE company_id=@company AND role='admin' AND active=true AND password_hash IS NOT NULL",
      ),
      parameters: {'company': row[0]},
    );
    if ((count.first.first as int) <= 1) return false;
  }
  await tx.execute(
    Sql.named(
      'UPDATE users SET active=@active,auth_epoch=auth_epoch+1 WHERE id=@id',
    ),
    parameters: {'active': active, 'id': id},
  );
  await tx.execute(
    Sql.named('DELETE FROM user_sessions WHERE user_id=@id'),
    parameters: {'id': id},
  );
  return true;
}

class ManagedCompanies {
  ManagedCompanies(this.db, this.internalToken);
  final Connection db;
  final String internalToken;
  Future<Response> handle(Request request) => apiGuard(() async {
    if (request.method != 'POST')
      return jsonError('POST erforderlich.', status: 405);
    if (internalToken.isEmpty ||
        request.headers['x-internal-token'] != internalToken)
      return jsonError('Nicht berechtigt.', status: 403);
    final b = await readJson(request);
    try {
      return jsonOk(await execute(b));
    } on ServerException catch (e) {
      if (e.code == '23505')
        return jsonError(
          'Benutzername oder Vorgang existiert bereits.',
          status: 409,
        );
      rethrow;
    }
  });
  Future<Json> execute(Json b) => db.runTx((tx) async {
    await tx.execute('SELECT pg_advisory_xact_lock(28471824)');
    final action = requiredText(b, 'action');
    final actor = requiredText(b, 'actor');
    if (action == 'list') {
      final rows = await tx.execute(
        'SELECT id,name,active,management_version FROM companies ORDER BY name',
      );
      return {
        'companies': [
          for (final r in rows)
            {
              'id': r[0],
              'name': r[1],
              'active': r[2],
              'version': r[3],
              'mode': 'managed',
            },
        ],
      };
    }
    if (action == 'create') {
      confirmed(b);
      final requestId = requiredText(b, 'requestId', max: 100);
      if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(requestId))
        throw ApiProblem(400, 'Ungültige Vorgangsnummer.');
      final id = 'managed-$requestId';
      final existing = await tx.execute(
        Sql.named('SELECT id,name FROM companies WHERE id=@id'),
        parameters: {'id': id},
      );
      if (existing.isNotEmpty)
        return {
          'id': id,
          'name': existing.first[1],
          'alreadyCreated': true,
          'message': 'Bereits angelegt; bei Bedarf Aktivierung neu ausstellen.',
        };
      final name = requiredText(b, 'name');
      final username = requiredText(b, 'username');
      final reason = requiredText(b, 'reason', max: 2000);
      await tx.execute(
        Sql.named('INSERT INTO companies(id,name) VALUES(@id,@name)'),
        parameters: {'id': id, 'name': name},
      );
      final admin = await _admin(tx, id, username);
      await _audit(tx, id, actor, action, reason, {
        'name': name,
        'userId': admin['userId'],
        'username': username,
      });
      return {'id': id, 'name': name, 'version': 1, ...admin};
    }
    final id = requiredText(b, 'companyId');
    final rows = await tx.execute(
      Sql.named('SELECT active,management_version FROM companies WHERE id=@id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty)
      throw ApiProblem(
        404,
        'Lokales Managed-Backend nicht gefunden. Externe Backends werden hier nicht gesteuert.',
      );
    if (action == 'users') {
      final users = await tx.execute(
        Sql.named(
          'SELECT id,username,role,active,password_hash IS NOT NULL,auth_epoch FROM users WHERE company_id=@id ORDER BY username',
        ),
        parameters: {'id': id},
      );
      return {
        'users': [
          for (final u in users)
            {
              'id': u[0],
              'username': u[1],
              'role': u[2],
              'active': u[3],
              'activated': u[4],
              'version': u[5],
            },
        ],
      };
    }
    if (action == 'audit') {
      final entries = await tx.execute(
        Sql.named(
          'SELECT actor,action,reason,details,created_at FROM management_audit WHERE company_id=@id ORDER BY created_at,id',
        ),
        parameters: {'id': id},
      );
      return {
        'entries': [
          for (final e in entries)
            {
              'actor': e[0],
              'action': e[1],
              'reason': e[2],
              'details': e[3],
              'at': (e[4] as DateTime).toUtc().toIso8601String(),
            },
        ],
      };
    }
    confirmed(b);
    final reason = requiredText(b, 'reason', max: 2000);
    if (action == 'access') {
      if (expectedVersion(b) != rows.first[1]) throw Conflict();
      final active = b['active'];
      if (active is! bool) throw ApiProblem(400, 'active erforderlich.');
      await tx.execute(
        Sql.named(
          'UPDATE companies SET active=@active,management_version=management_version+1,auth_epoch=auth_epoch+1 WHERE id=@id',
        ),
        parameters: {'id': id, 'active': active},
      );
      await tx.execute(
        Sql.named('DELETE FROM user_sessions WHERE company_id=@id'),
        parameters: {'id': id},
      );
      await _audit(tx, id, actor, action, reason, {
        'previousActive': rows.first[0],
        'active': active,
        'version': (rows.first[1] as int) + 1,
      });
      return {
        'id': id,
        'active': active,
        'version': (rows.first[1] as int) + 1,
      };
    }
    if (action == 'addAdmin') {
      final admin = await _admin(tx, id, requiredText(b, 'username'));
      await _audit(tx, id, actor, action, reason, {
        'userId': admin['userId'],
        'username': admin['username'],
      });
      return admin;
    }
    final userId = requiredText(b, 'userId');
    final users = await tx.execute(
      Sql.named(
        'SELECT auth_epoch FROM users WHERE id=@user AND company_id=@company',
      ),
      parameters: {'user': userId, 'company': id},
    );
    if (users.isEmpty) throw ApiProblem(404, 'Zugang nicht gefunden.');
    if (expectedVersion(b) != users.first[0]) throw Conflict();
    if (action == 'userAccess') {
      final active = b['active'];
      if (active is! bool) throw ApiProblem(400, 'active erforderlich.');
      if (!await safeUserActive(tx, userId, active))
        throw ApiProblem(
          409,
          'Letzten aktiven Admin kann niemand deaktivieren.',
        );
      await _audit(tx, id, actor, action, reason, {
        'userId': userId,
        'active': active,
      });
      return {'id': userId, 'active': active};
    }
    if (action == 'activation') {
      // A recovery invitation invalidates older invitations and live sessions.
      // Existing password remains usable until redemption (avoids locking out last admin).
      await tx.execute(
        Sql.named(
          'UPDATE activation_tokens SET used_at=now() WHERE user_id=@id AND used_at IS NULL',
        ),
        parameters: {'id': userId},
      );
      await tx.execute(
        Sql.named('UPDATE users SET auth_epoch=auth_epoch+1 WHERE id=@id'),
        parameters: {'id': userId},
      );
      await tx.execute(
        Sql.named('DELETE FROM user_sessions WHERE user_id=@id'),
        parameters: {'id': userId},
      );
      final token = await _activation(tx, userId);
      await _audit(tx, id, actor, action, reason, {'userId': userId});
      return {'userId': userId, 'activationToken': token};
    }
    throw ApiProblem(400, 'Unbekannte Aktion.');
  });
  Future<Json> _admin(TxSession tx, String company, String username) async {
    final id = 'user-${SessionTokens.generate()}';
    await tx.execute(
      Sql.named(
        "INSERT INTO users(id,company_id,username,role) VALUES(@id,@company,@username,'admin')",
      ),
      parameters: {'id': id, 'company': company, 'username': username},
    );
    return {
      'userId': id,
      'username': username,
      'activationToken': await _activation(tx, id),
    };
  }

  Future<String> _activation(TxSession tx, String user) async {
    final token = SessionTokens.generate();
    await tx.execute(
      Sql.named(
        "INSERT INTO activation_tokens(token_hash,user_id,expires_at) VALUES(@hash,@user,now()+interval '7 days')",
      ),
      parameters: {'hash': SessionTokens.hashOf(token), 'user': user},
    );
    return token;
  }

  Future<void> _audit(
    TxSession tx,
    String company,
    String actor,
    String action,
    String reason,
    Json details,
  ) => tx
      .execute(
        Sql.named(
          'INSERT INTO management_audit(id,company_id,actor,action,reason,details) VALUES(@id,@company,@actor,@action,@reason,CAST(@details AS jsonb))',
        ),
        parameters: {
          'id': SessionTokens.generate(),
          'company': company,
          'actor': actor,
          'action': action,
          'reason': reason,
          'details': jsonEncode(details),
        },
      )
      .then((_) {});
}
