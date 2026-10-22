import 'package:bcrypt/bcrypt.dart';

/// Passwort-Hashing für alle LibreECAD-Backend-Dienste. Bewusst
/// bcrypt statt eines eigenen Verfahrens — etabliertes, langsames
/// Hash-Verfahren mit eingebautem Salt, kein Grund, hier etwas
/// Eigenes zu bauen.
class Passwords {
  Passwords._();

  static String hash(String plainText) => BCrypt.hashpw(plainText, BCrypt.gensalt());

  static bool verify(String plainText, String hash) {
    try {
      return BCrypt.checkpw(plainText, hash);
    } on ArgumentError {
      // Ungültiger/beschädigter Hash in der DB (z. B. durch
      // manipulierte Testdaten) — als "falsches Passwort" behandeln
      // statt den Request mit 500 abzubrechen.
      return false;
    } on FormatException {
      return false;
    }
  }
}
