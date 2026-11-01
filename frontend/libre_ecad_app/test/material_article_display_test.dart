import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/screens/documents_screen.dart';

void main() {
  test('catalog-linked material row shows model, number and readable type', () {
    final row = displayMaterialRow({
      'bmk': '1-Q1',
      'label': 'Leitungsschutzschalter 1-polig',
      'type': 'mcb1',
      'article': {
        'number': 'DEMO-236', 'name': 'TEST-B16/1', 'manufacturer': 'FIKTIV',
      },
    });
    expect(row['label'], 'TEST-B16/1');
    expect(row['articleNumber'], 'DEMO-236');
    expect(row['type'], 'Leitungsschutzschalter 1-polig');
  });
  test('material table ends with semicolon-joined BMKs', () {
    expect(materialTableFields.keys.toList(), [
      'articleNumber', 'label', 'type', 'quantity', 'positions', 'bmk',
    ]);
    expect(materialTableFields.values.last, 'BMK');
    final row = displayMaterialRow({
      'bmk': 'Q1; Q2', 'label': 'TEST-B16/1', 'type': 'mcb1',
      'quantity': 2, 'articleNumber': 'DEMO-236',
    });
    expect(row['bmk'], 'Q1; Q2');
    expect(row['quantity'], 2);
  });
}
