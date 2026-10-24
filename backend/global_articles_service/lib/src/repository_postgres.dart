import 'package:postgres/postgres.dart';

import 'models.dart';
import 'repository.dart';

class PostgresArticleRepository implements ArticleRepository {
  PostgresArticleRepository(this._db);
  final Session _db;

  @override
  Future<bool> isEmpty() async {
    final result = await _db.execute('SELECT count(*) FROM articles');
    return (result.first.first as int) == 0;
  }

  @override
  Future<void> insertAll(List<Article> articles) async {
    for (final article in articles) {
      await _db.execute(
        Sql.named('''
          INSERT INTO articles (id, article_number, name, source, manufacturer_name, version)
          VALUES (@id, @articleNumber, @name, @source, @manufacturerName, @version)
          ON CONFLICT (id) DO NOTHING
        '''),
        parameters: {
          'id': article.id,
          'articleNumber': article.articleNumber,
          'name': article.name,
          'source': article.source.wireValue,
          'manufacturerName': article.manufacturerName,
          'version': article.version,
        },
      );
    }
  }

  @override
  Future<Article?> findById(String id) async {
    final result = await _db.execute(
      Sql.named(
        'SELECT id, article_number, name, source, manufacturer_name, version FROM articles WHERE id = @id',
      ),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _toArticle(result.first);
  }

  @override
  Future<List<Article>> search(String query) async {
    final result = await _db.execute(
      Sql.named('''
        SELECT id, article_number, name, source, manufacturer_name, version FROM articles
        WHERE article_number ILIKE @needle OR name ILIKE @needle
        ORDER BY article_number
      '''),
      parameters: {'needle': '%$query%'},
    );
    return [for (final row in result) _toArticle(row)];
  }

  Article _toArticle(ResultRow row) => Article(
        id: row[0] as String,
        articleNumber: row[1] as String,
        name: row[2] as String,
        source: ArticleSourceJson.fromWire(row[3] as String),
        manufacturerName: row[4] as String?,
        version: row[5] as int,
      );
}
