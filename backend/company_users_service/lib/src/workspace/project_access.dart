import '../models.dart';
import 'store.dart';

/// Resolve current group grants on every request, also for offline/API access.
Future<bool> projectVisible(
  WorkspaceStore store,
  Document project,
  AppUser user,
) async {
  if (user.role == UserRole.admin ||
      (project['memberIds'] as List).contains(user.id))
    return true;
  for (final id in project['groupIds'] as List? ?? []) {
    final group = await store.get(user.companyId, 'projectGroup', id);
    if (group != null && (group['memberIds'] as List).contains(user.id))
      return true;
  }
  return false;
}
