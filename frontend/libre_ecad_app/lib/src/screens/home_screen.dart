import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/company_users_api.dart';
import '../models.dart';
import '../session_service.dart';
import '../app_theme.dart';
import '../workspace_shell.dart';
import 'login_screen.dart';

/// Bereich „Arbeitsplatz“ innerhalb der [WorkspaceShell]: Firmenname,
/// Rolle, Schnellzugriff auf die Bereiche, Benutzerverwaltung für
/// Admins und die Erreichbarkeitsprobe des globalen Katalogs. Die
/// Bereichsnavigation selbst liegt in der Shell.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<SessionService>().logout();
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>().session;
    if (session == null) return const SizedBox.shrink();
    final isAdmin = session.role == UserRole.admin;
    final sections = workspaceSections(session);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbeitsplatz'),
        actions: [
          Chip(label: Text(isAdmin ? 'Firmenadmin' : 'Zeichner')),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: () => _logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
        children: [
          const Text(
            'FIRMENARBEITSPLATZ',
            style: TextStyle(color: ecadGold, letterSpacing: 2, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            isAdmin
                ? 'Team und Projekte im Blick.'
                : 'Bereit für Ihren nächsten Plan.',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Angemeldet als ${session.username} (${isAdmin ? 'Admin' : 'Zeichner'}) · ${session.companyName}',
            style: const TextStyle(color: ecadMuted),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _OverviewCard(
                label: 'FIRMA',
                value: session.companyName,
                icon: Icons.business_outlined,
              ),
              _OverviewCard(
                label: 'ZUGANG',
                value: isAdmin ? 'Firmenverwaltung' : 'Projektbearbeitung',
                icon: Icons.badge_outlined,
              ),
              _OverviewCard(
                label: 'BACKEND',
                value: session.backendUrl.host,
                icon: Icons.dns_outlined,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Bereiche', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // Index 0 ist dieser Arbeitsplatz selbst.
              for (var i = 1; i < sections.length; i++)
                _SectionShortcut(
                  section: sections[i],
                  onTap: () => WorkspaceShell.open(context, i),
                ),
            ],
          ),
          const SizedBox(height: 28),
          if (isAdmin)
            LayoutBuilder(
              builder: (context, constraints) {
                final backend = _BackendCard(session: session);
                if (constraints.maxWidth < 1000) {
                  return Column(
                    children: [
                      const _AdminUserManagement(),
                      const SizedBox(height: 16),
                      backend,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(flex: 2, child: _AdminUserManagement()),
                    const SizedBox(width: 16),
                    Expanded(child: backend),
                  ],
                );
              },
            )
          else
            const _ZeichnerPlaceholder(),
        ],
      ),
    );
  }
}

class _SectionShortcut extends StatelessWidget {
  const _SectionShortcut({required this.section, required this.onTap});
  final WorkspaceSection section;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(section.icon, color: ecadGold),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  section.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: ecadMuted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BackendCard extends StatelessWidget {
  const _BackendCard({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.dns_outlined, color: ecadGold),
          const SizedBox(height: 18),
          Text(
            'Ihr Firmen-Backend',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SelectableText(
            '${session.backendUrl}',
            style: const TextStyle(color: ecadMuted),
          ),
          const Divider(height: 32),
          const Text(
            'Anmeldung und Projektdaten laufen über diesen Server. Benutzerrechte gelten innerhalb Ihrer Firma.',
            style: TextStyle(height: 1.6, color: ecadMuted),
          ),
        ],
      ),
    ),
  );
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 310,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: ecadMuted,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Icon(icon, color: ecadGold),
              ],
            ),
            const SizedBox(height: 20),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}

class _ZeichnerPlaceholder extends StatelessWidget {
  const _ZeichnerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Der Schaltplaneditor ist über die zugewiesenen Projekte erreichbar. '
          'Dieser Zugang hat keine Administrationsrechte.',
        ),
      ),
    );
  }
}

class _AdminUserManagement extends StatefulWidget {
  const _AdminUserManagement();

  @override
  State<_AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<_AdminUserManagement> {
  late Future<List<CompanyUserListEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CompanyUserListEntry>> _load() {
    final session = context.read<SessionService>().session!;
    return context
        .read<SessionService>()
        .companyUsersApiFor(session.backendUrl)
        .listUsers(session.token);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _createZeichner() async {
    final usernameCtrl = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zeichner anlegen'),
        content: TextField(
          controller: usernameCtrl,
          decoration: const InputDecoration(labelText: 'Benutzername'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, usernameCtrl.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    if (username == null || username.isEmpty || !mounted) return;

    final session = context.read<SessionService>().session!;
    try {
      final activationToken = await context
          .read<SessionService>()
          .companyUsersApiFor(session.backendUrl)
          .createZeichner(session.token, username: username);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Zeichner angelegt'),
          content: SelectableText(
            'Aktivierungstoken für "$username" (noch kein Versandweg in M1, bitte selbst '
            'weitergeben):\n\n$activationToken',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _toggleActive(CompanyUserListEntry user) async {
    final session = context.read<SessionService>().session!;
    try {
      await context
          .read<SessionService>()
          .companyUsersApiFor(session.backendUrl)
          .setUserActive(session.token, userId: user.id, active: !user.active);
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'Benutzer dieser Firma',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.icon(
                  onPressed: _createZeichner,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Zeichner anlegen'),
                ),
              ],
            ),
            FutureBuilder<List<CompanyUserListEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Nutzer konnten nicht geladen werden: ${snapshot.error}',
                  );
                }
                final users = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      '${users.length} Zugänge · ${users.where((u) => u.active && u.activated).length} aktiv',
                      style: const TextStyle(color: ecadMuted),
                    ),
                    const Divider(height: 28),
                    for (final user in users)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ecadSelected,
                          child: Text(
                            user.username.isEmpty
                                ? '?'
                                : user.username[0].toUpperCase(),
                            style: const TextStyle(color: ecadGold),
                          ),
                        ),
                        title: Text(user.username),
                        subtitle: Text(
                          '${user.role == UserRole.admin ? 'Admin' : 'Zeichner'}'
                          '${user.activated ? '' : ' · noch nicht aktiviert'}',
                        ),
                        trailing: Switch(
                          value: user.active,
                          onChanged: (_) => _toggleActive(user),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
