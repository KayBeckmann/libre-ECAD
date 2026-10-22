import 'models.dart';

abstract class ArticleRepository {
  /// `true`, wenn noch keine Artikel existieren — steuert das
  /// Einspielen der Testdaten beim Start.
  Future<bool> isEmpty();

  Future<void> insertAll(List<Article> articles);

  Future<Article?> findById(String id);

  /// Suche über Artikelnummer/Bezeichnung (Fallunabhängig, Teilstring)
  /// — Abnahme M1.2: "Artikelnummer/Bezeichnung suchbar; Testtreffer
  /// aus den drei Bereichen zeigen richtige Herkunft/Version."
  Future<List<Article>> search(String query);
}
