import 'package:postgres/postgres.dart';

/// M1 schema remains the baseline. Each following migration runs once, in a
/// transaction, with an advisory lock protecting concurrent service starts.
Future<void> migrateWorkspace(Connection db) async {
  await db.runTx((tx) async {
    await tx.execute('SELECT pg_advisory_xact_lock(28471822)');
    await tx.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations '
      '(version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())',
    );
    final done = await tx.execute(
      'SELECT version FROM schema_migrations WHERE version=2',
    );
    if (done.isNotEmpty) return;
    await tx.execute('''CREATE TABLE workspace_documents (
      company_id TEXT NOT NULL REFERENCES companies(id),
      kind TEXT NOT NULL CHECK (kind IN ('project','article')),
      id TEXT NOT NULL,
      version INTEGER NOT NULL CHECK (version > 0),
      document JSONB NOT NULL,
      PRIMARY KEY(company_id,kind,id),
      CHECK ((document->>'version')::integer = version),
      CHECK (document->>'id' = id)
    )''');
    await tx.execute('''CREATE TABLE workspace_history (
      company_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      id TEXT NOT NULL,
      version INTEGER NOT NULL,
      document JSONB NOT NULL,
      PRIMARY KEY(company_id,kind,id,version),
      FOREIGN KEY(company_id,kind,id) REFERENCES workspace_documents(company_id,kind,id)
    )''');
    await tx.execute('INSERT INTO schema_migrations(version) VALUES (2)');
  });
}
