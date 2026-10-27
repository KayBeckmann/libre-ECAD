import 'package:shared_server_kit/shared_server_kit.dart';

import 'models.dart';
import 'repository.dart';

class InMemoryCompanyUserRepository implements CompanyUserRepository {
  final List<Company> _companies = [];
  final List<AppUser> _users = [];
  final List<ActivationToken> _activationTokens = [];
  final List<UserSession> _sessions = [];

  @override
  Future<Company> createCompany({
    required String id,
    required String name,
  }) async {
    final company = Company(id: id, name: name, active: true);
    _companies.add(company);
    return company;
  }

  @override
  Future<Company?> findCompanyById(String id) async =>
      _companies.where((c) => c.id == id).firstOrNull;

  @override
  Future<({AppUser user, String rawActivationToken})> createUser({
    required String id,
    required String companyId,
    required String username,
    required UserRole role,
  }) async {
    final user = AppUser(
      id: id,
      companyId: companyId,
      username: username,
      role: role,
      active: true,
    );
    _users.add(user);

    final rawToken = SessionTokens.generate();
    _activationTokens.add(
      ActivationToken(
        tokenHash: SessionTokens.hashOf(rawToken),
        userId: id,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        usedAt: null,
      ),
    );
    return (user: user, rawActivationToken: rawToken);
  }

  @override
  Future<AppUser?> findUserByUsername(String username) async =>
      _users.where((u) => u.username == username).firstOrNull;

  @override
  Future<AppUser?> findUserById(String id) async =>
      _users.where((u) => u.id == id).firstOrNull;

  @override
  Future<List<AppUser>> listUsersForCompany(String companyId) async =>
      _users.where((u) => u.companyId == companyId).toList();

  @override
  Future<int> countActiveActivatedAdmins(String companyId) async => _users
      .where(
        (u) =>
            u.companyId == companyId &&
            u.role == UserRole.admin &&
            u.active &&
            u.isActivated,
      )
      .length;

  @override
  Future<bool> setUserActive({required String id, required bool active}) async {
    final index = _users.indexWhere((u) => u.id == id);
    if (index == -1) return false;
    final existing = _users[index];
    _users[index] = AppUser(
      id: existing.id,
      companyId: existing.companyId,
      username: existing.username,
      role: existing.role,
      active: active,
      passwordHash: existing.passwordHash,
    );
    return true;
  }

  @override
  Future<bool> activateWithToken({
    required String rawToken,
    required String passwordHash,
  }) async {
    final tokenHash = SessionTokens.hashOf(rawToken);
    final tokenIndex = _activationTokens.indexWhere(
      (t) => t.tokenHash == tokenHash,
    );
    if (tokenIndex == -1) return false;
    final token = _activationTokens[tokenIndex];
    if (!token.isValid(DateTime.now().toUtc())) return false;

    final userIndex = _users.indexWhere((u) => u.id == token.userId);
    if (userIndex == -1) return false;
    final existing = _users[userIndex];
    _users[userIndex] = AppUser(
      id: existing.id,
      companyId: existing.companyId,
      username: existing.username,
      role: existing.role,
      active: existing.active,
      passwordHash: passwordHash,
    );
    _activationTokens[tokenIndex] = ActivationToken(
      tokenHash: token.tokenHash,
      userId: token.userId,
      expiresAt: token.expiresAt,
      usedAt: DateTime.now().toUtc(),
    );
    return true;
  }

  @override
  Future<bool> changeOwnPassword({
    required String userId,
    required String currentPassword,
    required String newPasswordHash,
  }) async {
    final index = _users.indexWhere((u) => u.id == userId);
    if (index < 0) return false;
    final existing = _users[index];
    if (!existing.active ||
        existing.passwordHash == null ||
        !Passwords.verify(currentPassword, existing.passwordHash!))
      return false;
    _users[index] = AppUser(
      id: existing.id,
      companyId: existing.companyId,
      username: existing.username,
      role: existing.role,
      active: existing.active,
      passwordHash: newPasswordHash,
      authEpoch: existing.authEpoch + 1,
    );
    _sessions.removeWhere((s) => s.userId == userId);
    return true;
  }

  @override
  Future<void> saveSession(UserSession session) async {
    _sessions.removeWhere((s) => s.tokenHash == session.tokenHash);
    _sessions.add(session);
  }

  @override
  Future<UserSession?> findSession(String tokenHash) async =>
      _sessions.where((s) => s.tokenHash == tokenHash).firstOrNull;

  @override
  Future<void> deleteSession(String tokenHash) async {
    _sessions.removeWhere((s) => s.tokenHash == tokenHash);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
