import 'package:postgres/postgres.dart';

Future<void> ensureSchema(Session db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS articles (
      id TEXT PRIMARY KEY,
      article_number TEXT NOT NULL,
      name TEXT NOT NULL,
      source TEXT NOT NULL,
      manufacturer_name TEXT,
      category TEXT,
      symbol_key TEXT,
      origin TEXT,
      version INTEGER NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  ''');
  // Altbestände behalten; CREATE TABLE IF NOT EXISTS erweitert sie nicht.
  await db.execute(
    'ALTER TABLE articles ADD COLUMN IF NOT EXISTS category TEXT',
  );
  await db.execute(
    'ALTER TABLE articles ADD COLUMN IF NOT EXISTS symbol_key TEXT',
  );
  await db.execute('ALTER TABLE articles ADD COLUMN IF NOT EXISTS origin TEXT');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS articles_search_idx ON articles (article_number, name);',
  );
}
