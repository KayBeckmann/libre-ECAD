import 'dart:convert';

import 'package:ecad_core/ecad_core.dart';

import '../../../backend/ecad_core/bin/planning_sample.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:libre_ecad_app/src/offline/vault.dart';
import 'package:libre_ecad_app/src/offline/offline_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'encrypted offline roundtrip, edit, PDF, expiry, tamper and disk CAS',
    () async {
      String? disk;
      var now = DateTime.utc(2026, 10, 25, 12);
      OfflineVault create() => OfflineVault(
        read: () async => disk,
        write: (expected, value) async {
          if (disk != expected) throw StateError('Concurrent disk change');
          disk = value;
        },
        clock: () => now,
      );
      final v = create();
      await v.unlock('test-passphrase');
      final packet = <String, dynamic>{
        'id': 'local',
        'userId': 'u',
        'companyId': 'c',
        'username': 'kay',
        'companyName': 'Secret Company',
        'backendUrl': 'http://127.0.0.1:1',
        'issuedAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(hours: 24)).toIso8601String(),
        'baseVersion': 3,
        'localRevision': 0,
        'library': pinnedLibrary(),
        'project': {
          'id': 'p',
          'name': 'Private project',
          'version': 3,
          'metadata': <String, dynamic>{},
          'drawing': sampleDrawing('motor'),
        },
      };
      await v.put(packet);
      expect(disk, isNot(contains('Private project')));
      expect(disk, isNot(contains('Secret Company')));
      expect(disk, isNot(contains('test-passphrase')));
      final original = disk;
      v.lock();
      expect(v.projects, isEmpty);
      await expectLater(v.unlock('incorrect-password'), throwsFormatException);
      expect(v.unlocked, isFalse);
      await v.unlock('test-passphrase');
      expect(v.get('local'), packet);
      final second = create();
      await second.unlock('test-passphrase');
      final api = OfflineApi(v, 'local');
      final edit = planningSample();
      await api.request('PUT', 'projects/p/drawing', {
        'version': 3,
        'drawing': edit,
      });
      expect(v.get('local')['localRevision'], 1);
      expect((await api.request('GET', 'projects/p/drawing'))['drawing'], edit);
      final documents = await api.request(
        'GET',
        'projects/p/documents?version=3',
      );
      expect(
        utf8.decode(base64Decode(documents['pdf']).take(4).toList()),
        '%PDF',
      );
      expect(documents['source'], 'offline');
      await expectLater(
        api.request('POST', 'projects/p/releases', {}),
        throwsException,
      );
      await expectLater(second.put(packet), throwsStateError);
      expect(second.get('local')['localRevision'], 0);
      now = now.add(const Duration(hours: 24));
      await expectLater(
        api.request('GET', 'projects/p/drawing'),
        throwsStateError,
      );
      expect(v.get('local')['project']['drawing'], edit);
      now = now.subtract(const Duration(hours: 25));
      expect(() => v.check(v.get('local')), throwsStateError);
      now = now.add(const Duration(hours: 1));
      final incompatible = cloneJson(v.get('local'))
        ..['library'] = <String, dynamic>{};
      expect(() => v.check(incompatible), throwsStateError);
      final envelope = jsonDecode(original!) as Map<String, dynamic>;
      final bytes = base64Decode(envelope['ciphertext']);
      bytes[0] ^= 1;
      envelope['ciphertext'] = base64Encode(bytes);
      disk = jsonEncode(envelope);
      await expectLater(
        create().unlock('test-passphrase'),
        throwsFormatException,
      );
      api.close();
    },
  );
}
