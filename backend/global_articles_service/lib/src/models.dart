/// Bereiche des globalen Artikelstamms. `catalog` kennzeichnet redaktionell
/// aus öffentlichen Quellen erfasste Daten; es ist keine verifizierte
/// Hersteller-Einreichung (`manufacturer`).
enum ArticleSource { general, manufacturer, catalog, userUpload }

extension ArticleSourceJson on ArticleSource {
  String get wireValue => switch (this) {
    ArticleSource.general => 'general',
    ArticleSource.manufacturer => 'manufacturer',
    ArticleSource.catalog => 'catalog',
    ArticleSource.userUpload => 'userUpload',
  };

  static ArticleSource fromWire(String value) => switch (value) {
    'general' => ArticleSource.general,
    'manufacturer' => ArticleSource.manufacturer,
    'catalog' => ArticleSource.catalog,
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
    this.category,
    this.symbolKey,
    this.origin,
  }) : assert(
         (source != ArticleSource.manufacturer &&
                 source != ArticleSource.catalog) ||
             manufacturerName != null,
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

  /// Fachliche Typgruppe; kein von einem Hersteller verifizierter Beitrag.
  final String? category;

  /// Wiederverwendbarer Bibliotheksschlüssel, null für reine Aufbauartikel.
  final String? symbolKey;

  /// Nachprüfbare, redaktionelle Quellenangabe zur Artikelvariante.
  final String? origin;
  final int version;

  Map<String, Object?> toJson() => {
    'id': id,
    'articleNumber': articleNumber,
    'name': name,
    'source': source.wireValue,
    'manufacturerName': manufacturerName,
    'category': category,
    'symbolKey': symbolKey,
    'origin': origin,
    'version': version,
  };
}
