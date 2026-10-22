import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:test/test.dart';

void main() {
  group('Passwords', () {
    test('verify() akzeptiert das richtige Passwort, lehnt ein falsches ab', () {
      final hash = Passwords.hash('korrektes-passwort');
      expect(Passwords.verify('korrektes-passwort', hash), isTrue);
      expect(Passwords.verify('falsches-passwort', hash), isFalse);
    });

    test('zwei Hashes desselben Passworts sind nie identisch (Salt)', () {
      final a = Passwords.hash('dasselbe');
      final b = Passwords.hash('dasselbe');
      expect(a, isNot(equals(b)));
    });

    test('verify() gegen einen beschädigten Hash liefert false statt zu werfen', () {
      expect(Passwords.verify('irgendwas', 'kein-gueltiger-bcrypt-hash'), isFalse);
    });
  });

  group('SessionTokens', () {
    test('generate() liefert nie zwei identische Tokens', () {
      final tokens = {for (var i = 0; i < 1000; i++) SessionTokens.generate()};
      expect(tokens, hasLength(1000));
    });

    test('hashOf() ist deterministisch für dasselbe Token, aber verschieden für andere', () {
      final token = SessionTokens.generate();
      expect(SessionTokens.hashOf(token), SessionTokens.hashOf(token));
      expect(SessionTokens.hashOf(token), isNot(equals(SessionTokens.hashOf(SessionTokens.generate()))));
    });
  });
}
