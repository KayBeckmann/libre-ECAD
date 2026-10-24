import 'package:postgres/postgres.dart';

Future<void> ensureSchema(Session db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS articles (
      id TEXT PRIMARY KEY,
      article_number TEXT NOT NULL,
      name TEXT NOT NULL,
      source TEXT NOT NULL,
      manufacturer_name TEXT,
      version INTEGER NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS articles_search_idx ON articles (article_number, name);');
}
