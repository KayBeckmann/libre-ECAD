import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../offline/offline_screen.dart';

import '../api/workspace_api.dart';
import '../api/company_users_api.dart';
import '../models.dart';
import 'drawing_screen.dart';
import 'automation_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.session});
  final Session session;
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final api = WorkspaceApi(widget.session);
  late Future<Map<String, dynamic>> data = api.request('GET', 'projects');
  void reload() => setState(() => data = api.request('GET', 'projects'));
  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  Future<void> edit([Map<String, dynamic>? project]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProjectEditor(session: widget.session, project: project),
      ),
    );
    if (changed == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Projekte')),
    floatingActionButton: widget.session.role == UserRole.admin
        ? FloatingActionButton.extended(
            onPressed: () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('Projekt anlegen'),
          )
        : null,
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${snapshot.error}'),
                TextButton(
                  onPressed: reload,
                  child: const Text('Erneut laden'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snapshot.data!['projects'] as List;
        if (projects.isEmpty) {
          return const Center(child: Text('Noch keine zugänglichen Projekte.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          itemCount: projects.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final p = projects[index] as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(p['name'] as String),
              subtitle: Text(
                'Arbeitsstand ${p['version']} · ${(p['memberIds'] as List).length} zugewiesene Nutzer',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () async {
                try {
                  final current = await api.request(
                    'GET',
                    'projects/${p['id']}',
                  );
                  if (mounted) {
                    await edit(current);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            );
          },
        );
      },
    ),
  );
}

class ProjectEditor extends StatefulWidget {
  const ProjectEditor({super.key, required this.session, this.project});
  final Session session;
  final Map<String, dynamic>? project;
  @override
  State<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<ProjectEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.project?['name'] as String? ?? '',
  );
  late final description = TextEditingController(
    text: widget.project?['description'] as String? ?? '',
  );
  late final Set<String> members = Set<String>.from(
    widget.project?['memberIds'] as List? ?? [],
  );
  late final metadata = {
    for (final key in [
      'Kunde',
      'Anlage',
      'Auftrag',
      'Baujahr',
      'Standort',
      'Verantwortlich',
      'Dokumentnummer',
    ])
      key: TextEditingController(
        text: widget.project?['metadata']?[key] as String? ?? '',
      ),
  };
  late final api = WorkspaceApi(widget.session);
  late final Future<List<CompanyUserListEntry>> users =
      widget.session.role == UserRole.admin
      ? CompanyUsersApi(baseUrl: widget.session.backendUrl)
            .listUsers(widget.session.token)
      : Future.value([]);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    for (final controller in metadata.values) {
      controller.dispose();
    }
    api.close();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.request(
        widget.project == null ? 'POST' : 'PATCH',
        widget.project == null
            ? 'projects'
            : 'projects/${widget.project!['id']}',
        {
          'name': name.text.trim(),
          'description': description.text.trim(),
          'metadata': {
            for (final entry in metadata.entries)
              entry.key: entry.value.text.trim(),
          },
          if (widget.session.role == UserRole.admin)
            'memberIds': members.toList(),
          if (widget.project != null) 'version': widget.project!['version'],
        },
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.project == null ? 'Neues Projekt' : 'Projekt öffnen'),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.project != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DrawingScreen(
                                session: widget.session,
                                projectId: widget.project!['id'],
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.polyline_outlined),
                    label: const Text('Schaltplan öffnen'),
                  ),
                ),
              if (widget.project != null)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AutomationScreen(
                              session: widget.session,
                              projectId: widget.project!['id'],
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.integration_instructions_outlined),
                  label: const Text('API / MCP'),
                ),
              if (!kIsWeb && widget.project != null)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => prepareOffline(
                          context,
                          widget.session,
                          widget.project!['id'],
                        ),
                  icon: const Icon(Icons.download),
                  label: const Text('Offline vorbereiten'),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Projektname'),
                maxLength: 200,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Projektname fehlt.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung / Arbeitsauftrag',
                ),
                maxLines: 4,
                maxLength: 4000,
              ),
              const SizedBox(height: 24),
              ExpansionTile(
                title: const Text('Deckblatt und Projektmetadaten'),
                children: [
                  for (final entry in metadata.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: entry.value,
                        maxLength: 160,
                        decoration: InputDecoration(labelText: entry.key),
                      ),
                    ),
                ],
              ),
              if (widget.session.role == UserRole.admin) ...[
                Text(
                  'Projektmitglieder',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Firmenadmins haben Zugriff auf alle Firmenprojekte. Zeichner erhalten Zugriff durch Zuweisung.',
                ),
                FutureBuilder<List<CompanyUserListEntry>>(
                  future: users,
                  builder: (context, s) {
                    if (s.hasError) {
                      return Text(
                        'Nutzer konnten nicht geladen werden: ${s.error}',
                      );
                    }
                    if (!s.hasData) {
                      return const LinearProgressIndicator();
                    }
                    return Column(
                      children: [
                        for (final u in s.data!.where(
                          (u) => u.active && u.activated,
                        ))
                          CheckboxListTile(
                            title: Text(u.username),
                            value: members.contains(u.id),
                            onChanged: busy
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      members.add(u.id);
                                    } else {
                                      members.remove(u.id);
                                    }
                                  }),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Projektstamm · Zeichnung und Metadaten teilen denselben Arbeitsstand. Keine fachliche Freigabe.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(busy ? 'Speichert …' : 'Projekt speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
