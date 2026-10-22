import 'models.dart';
import 'repository.dart';

class InMemoryArticleRepository implements ArticleRepository {
  final List<Article> _articles = [];

  @override
  Future<bool> isEmpty() async => _articles.isEmpty;

  @override
  Future<void> insertAll(List<Article> articles) async => _articles.addAll(articles);

  @override
  Future<Article?> findById(String id) async {
    for (final article in _articles) {
      if (article.id == id) return article;
    }
    return null;
  }

  @override
  Future<List<Article>> search(String query) async {
    final needle = query.toLowerCase();
    return _articles
        .where(
          (a) => a.articleNumber.toLowerCase().contains(needle) || a.name.toLowerCase().contains(needle),
        )
        .toList();
  }
}
