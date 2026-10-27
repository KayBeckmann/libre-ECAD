import 'models.dart';

abstract class CompanyUserRepository {
  Future<Company> createCompany({required String id, required String name});

  Future<Company?> findCompanyById(String id);

  /// Legt einen Nutzer **ohne** Passwort an (siehe [AppUser.passwordHash])
  /// und gleich ein dazugehöriges [ActivationToken]; gibt das
  /// **rohe** (nicht gehashte) Aktivierungstoken zurück — nur dieser
  /// Rückgabewert, nie die DB, enthält das Klartext-Token.
  Future<({AppUser user, String rawActivationToken})> createUser({
    required String id,
    required String companyId,
    required String username,
    required UserRole role,
  });

  Future<AppUser?> findUserByUsername(String username);

  Future<AppUser?> findUserById(String id);

  Future<List<AppUser>> listUsersForCompany(String companyId);

  /// Wie viele **aktive, bereits aktivierte** Admins hat diese Firma —
  /// für den "letzten Admin nicht aussperren"-Schutz.
  Future<int> countActiveActivatedAdmins(String companyId);

  Future<bool> setUserActive({required String id, required bool active});

  /// Löst das Aktivierungstoken ein: setzt das Passwort, markiert das
  /// Token als benutzt. `false`, wenn das Token ungültig/abgelaufen/
  /// bereits benutzt ist — setzt dann **nichts**.
  Future<bool> activateWithToken({
    required String rawToken,
    required String passwordHash,
  });

  /// Atomically verify the current password and revoke all sessions on change.
  Future<bool> changeOwnPassword({
    required String userId,
    required String currentPassword,
    required String newPasswordHash,
  });

  Future<void> saveSession(UserSession session);

  Future<UserSession?> findSession(String tokenHash);

  Future<void> deleteSession(String tokenHash);
}
