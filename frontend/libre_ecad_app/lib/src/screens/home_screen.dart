import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/company_users_api.dart';
import '../models.dart';
import '../session_service.dart';
import 'article_search_demo.dart';
import 'login_screen.dart';
import 'projects_screen.dart';
import 'articles_screen.dart';

/// M1.4 — "Minimaler Startbildschirm mit Firmenname, Rolle und
/// Abmelden." Admin sieht Benutzerübersicht + Anlegen/Deaktivieren;
/// Zeichner sieht nur eigenen Zugang + Hinweis, dass der
/// Zeichenbereich erst später kommt.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<SessionService>().logout();
    if (!context.mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>().session!;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.companyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Angemeldet als ${session.username} (${session.role == UserRole.admin ? 'Admin' : 'Zeichner'})',
          ),
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Projekte'),
            subtitle: const Text('Firmenprojekte öffnen und verwalten'), trailing: const Icon(Icons.arrow_forward),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectsScreen(session: session)))),
          ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Artikelbibliothek'),
            subtitle: const Text('Persönliche Artikel, Firmenstamm und Baukasten'), trailing: const Icon(Icons.arrow_forward),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticlesScreen(session: session)))),
          if (session.role == UserRole.admin)
            const _AdminUserManagement()
          else
            const _ZeichnerPlaceholder(),
          const SizedBox(height: 16),
          FutureBuilder<String>(
            future: context.read<SessionService>().loadGlobalArticlesUrl(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return ArticleSearchDemo(globalArticlesUrl: snapshot.data!);
            },
          ),
        ],
      ),
    );
  }
}

class _ZeichnerPlaceholder extends StatelessWidget {
  const _ZeichnerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Der Schaltplaneditor kommt erst in einem späteren '
          'Meilenstein. Dieser Zugang kann sich anmelden, hat aber keine '
          'Administrationsrechte.',
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Benutzer dieser Firma',
                  style: Theme.of(context).textTheme.titleSmall,
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
                  return Text('Nutzer konnten nicht geladen werden: ${snapshot.error}');
                }
                final users = snapshot.data!;
                return Column(
                  children: [
                    for (final user in users)
                      ListTile(
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
