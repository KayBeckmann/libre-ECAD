/// M1.2 — drei getrennte Bereiche des einen logisch globalen
/// Artikelstamms (Brainstorming: "Allgemeine Artikel, Hersteller-
/// Daten ... je Hersteller, User-Uploads"). Kein Upload in M1 — nur
/// Lesen/Suchen von Testdaten.
enum ArticleSource { general, manufacturer, userUpload }

extension ArticleSourceJson on ArticleSource {
  String get wireValue => switch (this) {
        ArticleSource.general => 'general',
        ArticleSource.manufacturer => 'manufacturer',
        ArticleSource.userUpload => 'userUpload',
      };

  static ArticleSource fromWire(String value) => switch (value) {
        'general' => ArticleSource.general,
        'manufacturer' => ArticleSource.manufacturer,
        'userUpload' => ArticleSource.userUpload,
        _ => throw ArgumentError('Unbekannte ArticleSource: $value'),
      };
}

class Article {
  const Article({
    required this.id,
    required this.articleNumber,
    required this.name,
    required this.source,
    required this.version,
    this.manufacturerName,
  }) : assert(
          source != ArticleSource.manufacturer || manufacturerName != null,
          'Hersteller-Artikel brauchen einen manufacturerName (siehe Roadmap: '
          '"verifizierte Herstellerdaten je Hersteller").',
        );

  final String id;
  final String articleNumber;
  final String name;
  final ArticleSource source;

  /// Nur bei [ArticleSource.manufacturer] gesetzt — "innerhalb eines
  /// eigenen Bereichs je Hersteller" (Brainstorming).
  final String? manufacturerName;
  final int version;

  Map<String, Object?> toJson() => {
        'id': id,
        'articleNumber': articleNumber,
        'name': name,
        'source': source.wireValue,
        'manufacturerName': manufacturerName,
        'version': version,
      };
}
