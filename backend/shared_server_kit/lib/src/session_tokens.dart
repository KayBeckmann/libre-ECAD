import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Opake Session-/Aktivierungstokens (siehe `docs/architecture.md`:
/// bewusst kein JWT, serverseitig sofort und zuverlässig widerrufbar).
/// Das Rohtoken wird einmalig an den Client ausgegeben, die DB
/// speichert **nur den Hash** — ein DB-Leak allein liefert damit keine
/// gültigen Sitzungen.
class SessionTokens {
  SessionTokens._();

  static final _random = Random.secure();

  /// 256-Bit-Zufallstoken, URL-sicher Base64-kodiert.
  static String generate() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// SHA-256 des Rohtokens — das, was tatsächlich in der DB landet.
  static String hashOf(String rawToken) => sha256.convert(utf8.encode(rawToken)).toString();
}
