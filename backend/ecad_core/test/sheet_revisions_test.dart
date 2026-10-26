import 'package:ecad_core/ecad_core.dart';
import 'package:test/test.dart';

void main() {
  test('old drawings remain valid without revision metadata', () {
    final drawing = emptyDrawing();
    expect(validateDrawing(drawing), equals(drawing));
  });

  test('optional dated revisions survive validation and JSON round trip', () {
    final drawing = emptyDrawing();
    objects(drawing, 'sheets').first['revisions'] = [
      {'revision': 'A', 'date': '2025-02-28', 'note': 'Prüfung'},
      {'revision': 'B', 'date': '2025-03-01'},
    ];
    expect(validateDrawing(cloneJson(drawing)), equals(drawing));
  });

  test('rejects invalid revision entries and excessive metadata', () {
    final drawing = emptyDrawing();
    final sheet = objects(drawing, 'sheets').first;
    for (final bad in [
      [
        {'revision': 'A', 'date': '2025-02-29'},
      ],
      [
        {'revision': 'A', 'date': '2025-01-01', 'note': ''},
      ],
      [
        {'revision': 'A', 'date': '2025-01-01', 'extra': 'x'},
      ],
      [
        {'revision': 'A', 'date': '2025-01-01'},
        {'revision': 'A', 'date': '2025-02-01'},
      ],
      List.generate(21, (i) => {'revision': '$i', 'date': '2025-01-01'}),
    ]) {
      sheet['revisions'] = bad;
      expect(
        () => validateDrawing(drawing),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });
}
