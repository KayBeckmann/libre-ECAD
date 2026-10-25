import 'dart:convert';
import 'dart:io';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libre_ecad_app/src/offline/vault.dart';
import 'package:libre_ecad_app/src/offline/offline_api.dart';
import 'package:libre_ecad_app/src/offline/storage.dart' as disk;
import 'package:libre_ecad_app/src/screens/drawing_screen.dart';

class NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError('Network forbidden in native offline acceptance');
}
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native encrypted restart, offline editor and PDF without network', (tester) async {
    // Run with a fresh XDG_DATA_HOME: never touch a real user vault.
    expect(Platform.environment['XDG_DATA_HOME'], contains('libre-ecad-native-test-'));
    final v = OfflineVault();
    await v.unlock('native-test-passphrase');
    final now = DateTime.now().toUtc();
    await v.put({'id':'native-test','userId':'u','companyId':'c','username':'test','companyName':'TEST',
      'backendUrl':'http://127.0.0.1:1','issuedAt':now.toIso8601String(),
      'expiresAt':now.add(const Duration(hours:24)).toIso8601String(),
      'baseVersion':1,'localRevision':0,'library':pinnedLibrary(),
      'project':{'id':'p','name':'Native Offline Test','version':1,'metadata':<String,dynamic>{},'drawing':sampleDrawing('motor')}});
    expect(await disk.readVault(), isNot(contains('Native Offline Test')));
    v.lock();
    final restarted = OfflineVault();
    await restarted.unlock('native-test-passphrase');
    final api = OfflineApi(restarted,'native-test');
    HttpOverrides.global = NoNetwork();
    addTearDown(() {HttpOverrides.global=null;api.close();});
    await tester.pumpWidget(MaterialApp(home:DrawingScreen(session:api.session,projectId:'p',api:api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('OFFLINE'), findsWidgets);
    final drawing = sampleDrawing('distribution');
    await api.request('PUT','projects/p/drawing',{'version':1,'drawing':drawing});
    final docs = await api.request('GET','projects/p/documents?version=1');
    final bytes = base64Decode(docs['pdf']);
    expect(utf8.decode(bytes.take(4).toList()),'%PDF');
    await File('${Platform.environment['XDG_DATA_HOME']}/offline-acceptance.pdf').writeAsBytes(bytes);
    restarted.lock();
    final check = OfflineVault();
    await check.unlock('native-test-passphrase');
    expect(check.get('native-test')['project']['drawing'],drawing);
    check.lock();
    await tester.pumpWidget(const SizedBox());
  });
}
