import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:ecad_core/ecad_core.dart';

import 'storage.dart' as disk;

/// No server session or login password is written. The vault password stays in
/// memory only as a derived key; authenticated encryption also covers metadata.
class OfflineVault {
  OfflineVault({
    this.read = disk.readVault,
    this.write = disk.writeVault,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final Future<String?> Function() read;
  final Future<void> Function(String?, String) write;
  final DateTime Function() clock;
  SecretKey? _key;
  List<int>? _salt;
  String? _stored;
  Json _data = {};
  final _cipher = AesGcm.with256bits();
  List<Json> get projects =>
      (_data['projects'] as List? ?? []).cast<Json>().map(cloneJson).toList();
  bool get unlocked => _key != null;
  Future<void> unlock(String password) async {
    if (password.length < 8) {
      throw FormatException('Lokales Passwort: mindestens 8 Zeichen.');
    }
    final raw = await read();
    final envelope = raw == null ? null : jsonDecode(raw) as Json;
    if (envelope != null && envelope['format'] != 'libre-ecad-vault-1') {
      throw FormatException('Unbekannte Ablageversion.');
    }
    final salt = envelope == null
        ? List<int>.generate(16, (_) => Random.secure().nextInt(256))
        : base64Decode(envelope['salt']);
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    Json data = {
      'projects': <Json>[],
      'lastSeen': clock().toUtc().toIso8601String(),
    };
    if (envelope != null) {
      try {
        data = jsonDecode(
          utf8.decode(
            await _cipher.decrypt(
              SecretBox(
                base64Decode(envelope['ciphertext']),
                nonce: base64Decode(envelope['nonce']),
                mac: Mac(base64Decode(envelope['mac'])),
              ),
              secretKey: key,
              aad: utf8.encode('libre-ecad-vault-1'),
            ),
          ),
        ) as Json;
      } on SecretBoxAuthenticationError {
        throw FormatException('Passwort falsch oder lokale Ablage beschädigt.');
      }
    }
    _key = key;
    _salt = salt;
    _stored = raw;
    _data = data;
  }

  void lock() {
    _key = null;
    _salt = null;
    _stored = null;
    _data = {};
  }

  Json get(String id) => projects.firstWhere((p) => p['id'] == id);
  void check(Json packet) {
    if (!unlocked) throw StateError('Lokale Ablage gesperrt.');
    final now = clock().toUtc();
    if (now.isBefore(
      DateTime.parse(_data['lastSeen']).subtract(const Duration(minutes: 5)),
    )) {
      throw StateError(
        'Gerätezeit wurde zurückgestellt. Online-Berechtigung erneut prüfen.',
      );
    }
    if (!now.isBefore(DateTime.parse(packet['expiresAt']))) {
      throw StateError(
        'Offline-Berechtigung abgelaufen. Online erneuern; lokale Änderungen bleiben gespeichert.',
      );
    }
    if (canonicalJson(packet['library']) != canonicalJson(pinnedLibrary())) {
      throw StateError('Diese Kopie benötigt einen anderen Bibliotheksstand.');
    }
  }

  Future<void> put(Json packet) async {
    if (!unlocked) throw StateError('Ablage gesperrt.');
    final next = cloneJson(_data);
    final projects = (next['projects'] as List);
    projects.removeWhere((p) => p['id'] == packet['id']);
    projects.add(cloneJson(packet));
    next['lastSeen'] = clock().toUtc().toIso8601String();
    await _save(next);
  }

  Future<void> remove(String id) async {
    final next = cloneJson(_data);
    (next['projects'] as List).removeWhere((p) => p['id'] == id);
    await _save(next);
  }

  Future<void> _save(Json next) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(next)),
      secretKey: _key!,
      aad: utf8.encode('libre-ecad-vault-1'),
    );
    final value = jsonEncode({
      'format': 'libre-ecad-vault-1',
      'salt': base64Encode(_salt!),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    await write(_stored, value);
    _stored = value;
    _data = next;
  }
}
