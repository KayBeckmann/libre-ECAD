import 'package:flutter/material.dart';

import '../api/workspace_api.dart';
import '../api/company_users_api.dart';
import '../models.dart';

class ProjectGroupsScreen extends StatefulWidget {
  const ProjectGroupsScreen({super.key, required this.session});
  final Session session;
  @override
  State<ProjectGroupsScreen> createState() => _ProjectGroupsScreenState();
}

class _ProjectGroupsScreenState extends State<ProjectGroupsScreen> {
  late final api = WorkspaceApi(widget.session);
  List<Map<String, dynamic>> groups = [];
  List<CompanyUserListEntry> users = [];
  String? error, employee;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await api.request('GET', 'project-groups');
      final people = await CompanyUsersApi(baseUrl: widget.session.backendUrl)
          .listUsers(widget.session.token);
      if (mounted) {
        setState(() {
          groups = (result['groups'] as List).cast<Map<String, dynamic>>();
          users = people.where((u) => u.active && u.activated).toList();
          error = null;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? old]) async {
    final name = TextEditingController(text: old?['name'] ?? '');
    final description = TextEditingController(text: old?['description'] ?? '');
    final members = Set<String>.from(old?['memberIds'] ?? []);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            old == null ? 'Projektgruppe anlegen' : 'Projektgruppe bearbeiten',
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Gruppenname'),
                  ),
                  TextField(
                    controller: description,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                    ),
                  ),
                  const Text(
                    'Freigeschaltete Mitarbeiter erhalten Zugriff auf alle zugeordneten Projekte. Direkte Projektzuweisungen bleiben zusätzlich bestehen.',
                  ),
                  for (final u in users)
                    CheckboxListTile(
                      value: members.contains(u.id),
                      title: Text(u.username),
                      onChanged: (v) => update(() {
                        v == true ? members.add(u.id) : members.remove(u.id);
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Gruppe speichern'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      setState(() => busy = true);
      try {
        await api.request(
          old == null ? 'POST' : 'PATCH',
          old == null ? 'project-groups' : 'project-groups/${old['id']}',
          {
            'name': name.text.trim(),
            'description': description.text.trim(),
            'memberIds': members.toList(),
            if (old != null) 'version': old['version'],
          },
        );
        await load();
      } catch (e) {
        if (mounted) {
          setState(() {
            error = '$e';
            busy = false;
          });
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    description.dispose();
  }

  Future<void> grant(Map<String, dynamic> group, bool value) async {
    final members = Set<String>.from(group['memberIds']);
    value ? members.add(employee!) : members.remove(employee);
    setState(() => busy = true);
    try {
      await api.request('PATCH', 'project-groups/${group['id']}', {
        ...group,
        'memberIds': members.toList(),
      });
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Projektgruppen & Mitarbeiter'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : () => edit(),
      label: const Text('Gruppe anlegen'),
      icon: const Icon(Icons.create_new_folder_outlined),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      children: [
        const Text(
          'Gruppenweise oder je Mitarbeiter zuweisen. Firmenadmins behalten Zugriff auf alle Firmenprojekte.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: employee ?? '',
          decoration: const InputDecoration(
            labelText: 'Gruppen für Mitarbeiter freischalten',
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Gruppen bearbeiten'),
            ),
            for (final u in users)
              DropdownMenuItem(value: u.id, child: Text(u.username)),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() => employee = v == '' ? null : v),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!busy && groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Noch keine Projektgruppen.'),
          ),
        for (final g in groups)
          employee == null
              ? ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: Text(g['name']),
                  subtitle: Text(
                    '${(g['memberIds'] as List).length} Mitarbeiter · Stand ${g['version']}',
                  ),
                  onTap: busy ? null : () => edit(g),
                )
              : CheckboxListTile(
                  title: Text(g['name']),
                  subtitle: Text(g['description']),
                  value: (g['memberIds'] as List).contains(employee),
                  onChanged: busy ? null : (v) => grant(g, v!),
                ),
      ],
    ),
  );
}
