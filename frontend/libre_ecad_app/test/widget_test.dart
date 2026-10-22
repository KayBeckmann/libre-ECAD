import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M1.4 — nur ein Smoke-Test, dass die App (Login-Bildschirm) ohne
/// Backend überhaupt rendert. Die eigentlichen Verhaltenstests gegen
/// Fakes/echte Dienste liegen in `test/login_flow_test.dart` und in
/// den Backend-Diensten selbst (`dart test`).
void main() {
  testWidgets('App startet auf dem Login-Bildschirm', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LibreEcadApp());
    await tester.pump();
    expect(find.text('LibreECAD'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
  });
}
