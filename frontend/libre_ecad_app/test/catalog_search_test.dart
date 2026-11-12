import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/screens/article_search_demo.dart';
import 'package:libre_ecad_app/src/models.dart';

void main() {
  test('Katalogtreffer übernimmt Kategorie und einmalige Symbolreferenz', () {
    final hit = GlobalArticleSearchHit.fromJson({
      'id': 'catalog-example',
      'version': 1,
      'articleNumber': 'DEMO-123',
      'name': 'Fiktiver Schutzschalter',
      'source': 'catalog',
      'manufacturerName': 'FIKTIV',
      'category': 'Schutzgeräte',
      'symbolKey': 'mcb1',
    });
    expect(hit.category, 'Schutzgeräte');
    expect(hit.symbolKey, 'mcb1');
    expect(catalogSymbolDescription(hit), 'Leitungsschutzschalter 1-polig');
  });
  testWidgets(
    'Herstellerkatalog ist Standardbereich der globalen Bauteilsuche',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArticleSearchDemo(
              globalArticlesUrl: 'https://example.invalid/api/global',
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'catalog',
      );
    },
  );
  testWidgets('Bauteilsuche bietet redaktionellen Herstellerkatalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArticleSearchDemo(
            globalArticlesUrl: 'https://example.invalid/api/global',
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Herstellerkataloge'), findsWidgets);
  });
}
