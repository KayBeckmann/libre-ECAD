import 'models.dart';

/// Synthetische Testdaten je Bereich (M1.2-Abnahme: "klare
/// Kennzeichnung als Beispieldaten"). **Keine echten Herstellerdaten**
/// — frei erfundene Nummern/Bezeichnungen zur Demonstration von
/// Suche/Herkunft/Version.
List<Article> buildSeedArticles() => [
      const Article(
        id: 'seed-general-1',
        articleNumber: 'ALLG-0001',
        name: 'Leitungsschutzschalter 1-polig 16A (Beispieldaten)',
        source: ArticleSource.general,
        version: 1,
      ),
      const Article(
        id: 'seed-general-2',
        articleNumber: 'ALLG-0002',
        name: 'Reihenklemme 2,5mm² (Beispieldaten)',
        source: ArticleSource.general,
        version: 1,
      ),
      const Article(
        id: 'seed-manufacturer-acme-1',
        articleNumber: 'ACME-100-16',
        name: 'ACME Leitungsschutzschalter B16 (Beispieldaten)',
        source: ArticleSource.manufacturer,
        manufacturerName: 'ACME',
        version: 1,
      ),
      const Article(
        id: 'seed-manufacturer-globex-1',
        articleNumber: 'GLX-7700',
        name: 'Globex Schütz 3-polig 25A (Beispieldaten)',
        source: ArticleSource.manufacturer,
        manufacturerName: 'Globex',
        version: 2,
      ),
      const Article(
        id: 'seed-user-upload-1',
        articleNumber: 'USER-0001',
        name: 'Community-Klemmenblock 4-fach (Beispieldaten, User-Upload)',
        source: ArticleSource.userUpload,
        version: 1,
      ),
    ];
