import 'package:postgres/postgres.dart';

/// Idempotentes Schema-Bootstrap statt eines eigenen Migrations-
/// werkzeugs (siehe `docs/architecture.md`) — für M1 ohne
/// Bestandsdaten ausreichend.
Future<void> ensureSchema(Connection db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS super_admins (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS super_admin_sessions (
      token_hash TEXT PRIMARY KEY,
      super_admin_id TEXT NOT NULL REFERENCES super_admins(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS audit_log (
      id TEXT PRIMARY KEY,
      super_admin_username TEXT NOT NULL,
      action TEXT NOT NULL,
      target TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL
    );
  ''');
}
