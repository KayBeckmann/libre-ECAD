import 'package:flutter/material.dart';
import 'package:ecad_core/ecad_core.dart';

import '../api/workspace_api.dart';
import '../api/company_users_api.dart';
import '../models.dart';
import '../screens/drawing_screen.dart';
import 'vault.dart';
import 'offline_api.dart';
import 'storage.dart' as disk;

Future<String?> secretDialog(
  BuildContext context,
  String title, {
  String? message,
  bool repeat = false,
}) async {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null) Text(message),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passwort'),
                validator: (v) =>
                    (v ?? '').length < 8 ? 'Mindestens 8 Zeichen.' : null,
              ),
              if (repeat) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passwort wiederholen',
                  ),
                  validator: (v) => v != password.text
                      ? 'Passwörter stimmen nicht überein.'
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(c, password.text);
          },
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  password.dispose();
  confirmation.dispose();
  return result;
}

Future<OfflineVault?> unlockVault(BuildContext context) async {
  final exists = await disk.readVault() != null;
  if (!context.mounted) return null;
  final password = await secretDialog(
    context,
    exists ? 'Lokale Ablage entsperren' : 'Lokale Ablage einrichten',
    repeat: !exists,
    message: 'Eigenes lokales Passwort. Die Ablage enthält keine Server-Sitzung. Ohne dieses Passwort können die verschlüsselten Kopien nicht geöffnet werden.',
  );
  if (password == null) return null;
  final vault = OfflineVault();
  await vault.unlock(password);
  return vault;
}

Future<void> prepareOffline(
  BuildContext context,
  Session session,
  String projectId,
) async {
  OfflineVault? vault;
  final api = WorkspaceApi(session);
  try {
    vault = await unlockVault(context);
    if (vault == null || !context.mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Projekt für Offline-Arbeit vorbereiten'),
        content: const Text(
          'Die gespeicherte Zeichnung und ihr Bibliotheksstand werden lokal verschlüsselt. Ein Entzug kann ohne Verbindung erst bei der nächsten Online-Prüfung erkannt werden. Die Offline-Berechtigung läuft automatisch ab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Jetzt herunterladen'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final packet = await api.request('POST', 'projects/$projectId/offline', {
      'confirmed': true,
    });
    packet['backendUrl'] = session.backendUrl.toString();
    await vault.put(packet);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Offline gespeichert. Berechtigt bis ${packet['expiresAt']}. Über „Offlineprojekte“ öffnen.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  } finally {
    vault?.lock();
    api.close();
  }
}

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});
  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  OfflineVault? vault;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    vault?.lock();
    super.dispose();
  }

  Future<void> unlock() async {
    setState(() => busy = true);
    try {
      final v = await unlockVault(context);
      if (mounted) setState(() => vault = v);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Json p) async {
    try {
      vault!.check(p);
      final api = OfflineApi(vault!, p['id']);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DrawingScreen(
            session: api.session,
            projectId: p['project']['id'],
            api: api,
          ),
        ),
      );
      api.close();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> online(Json packet, {required bool upload}) async {
    final password = await secretDialog(
      context,
      'Online bei ${packet['username']} anmelden',
      message:
          'Ziel: ${packet['backendUrl']}\nServer-Passwort eingeben. Lokale Ablage und Server-Anmeldung sind getrennt.',
    );
    if (password == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    Session? session;
    WorkspaceApi? api;
    final auth = CompanyUsersApi(baseUrl: Uri.parse(packet['backendUrl']));
    try {
      session = await auth
          .login(username: packet['username'], password: password)
          .timeout(const Duration(seconds: 15));
      api = WorkspaceApi(session);
      final base = 'projects/${packet['project']['id']}';
      final fresh = await api.request('POST', '$base/offline', {
        'confirmed': true,
      });
      if (fresh['userId'] != packet['userId'] ||
          fresh['companyId'] != packet['companyId']) {
        throw StateError('Zugang gehört nicht zur lokalen Kopie.');
      }
      if (!upload) {
        packet['issuedAt'] = fresh['issuedAt'];
        packet['expiresAt'] = fresh['expiresAt'];
        await vault!.put(packet);
      } else {
        final local = packet['project']['drawing'] as Json,
            remote = fresh['project']['drawing'] as Json;
        final changes = drawingChanges(remote, local);
        final conflict = fresh['baseVersion'] != packet['baseVersion'];
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              conflict
                  ? 'Versionskonflikt bewusst entscheiden'
                  : 'Offline-Entwurf hochladen',
            ),
            content: SizedBox(
              width: 1000,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lokale Basis V${packet['baseVersion']} / Server V${fresh['baseVersion']}. ${changes.length} abweichende Objekte. Nur die Zeichnung wird übernommen; Server-Metadaten bleiben erhalten. Keine fachliche Freigabe.',
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              'LOKAL\n${canonicalJson(local)}',
                            ),
                          ),
                        ),
                        const VerticalDivider(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              'SERVER\n${canonicalJson(remote)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Abbrechen / Entwurf behalten'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'server'),
                child: const Text('Serverzeichnung lokal übernehmen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'local'),
                child: const Text('Lokale Zeichnung bewusst hochladen'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        if (choice == 'local') {
          final saved = await api.request('POST', '$base/offline/upload', {
            'confirmed': true,
            'version': fresh['baseVersion'],
            'baseVersion': packet['baseVersion'],
            'userId': packet['userId'],
            'companyId': packet['companyId'],
            'drawing': local,
          });
          packet['baseVersion'] = saved['version'];
          packet['project'] = {
            ...fresh['project'],
            'version': saved['version'],
            'drawing': local,
          };
        } else {
          packet['baseVersion'] = fresh['baseVersion'];
          packet['project'] = fresh['project'];
        }
        packet['issuedAt'] = fresh['issuedAt'];
        packet['expiresAt'] = fresh['expiresAt'];
        packet['localRevision'] = 0;
        await vault!.put(packet);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      api?.close();
      if (session != null) {
        try {
          await auth.logout(session.token).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Offlineprojekte'),
      actions: [
        if (vault != null)
          TextButton(
            onPressed: busy
                ? null
                : () {
                    vault!.lock();
                    setState(() => vault = null);
                  },
            child: const Text('Sperren'),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Vorbereitete lokale Kopien',
          style: TextStyle(fontSize: 28),
        ),
        const SizedBox(height: 12),
        const Text(
          'Änderungen bleiben auf diesem Gerät. Upload erfolgt nur nach erneuter Anmeldung, Vergleich und Ihrer Entscheidung. Abgelaufene Kopien werden erhalten, bleiben aber bis zur Online-Erneuerung gesperrt.',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (vault == null)
          FilledButton(
            onPressed: busy ? null : unlock,
            child: const Text('Lokale Ablage entsperren'),
          ),
        if (vault != null && vault!.projects.isEmpty)
          const Text(
            'Noch keine vorbereiteten Projekte. Online ein Projekt öffnen und „Offline vorbereiten“ wählen.',
          ),
        if (vault != null)
          for (final p in vault!.projects)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['project']['name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${p['companyName']} · ${p['username']}\nBasis V${p['baseVersion']} · lokale Speicherungen ${p['localRevision']}\nBerechtigt bis ${p['expiresAt']}',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: busy ? null : () => open(p),
                          child: const Text('Offline öffnen'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => online(p, upload: false),
                          child: const Text('Berechtigung erneuern'),
                        ),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => online(p, upload: true),
                          child: const Text('Vergleichen und hochladen'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text(
                                        'Lokale Kopie löschen?',
                                      ),
                                      content: const Text(
                                        'Nicht hochgeladene Änderungen dieser Kopie gehen verloren.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Abbrechen'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('Löschen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes == true) {
                                    await vault!.remove(p['id']);
                                    if (mounted) setState(() {});
                                  }
                                },
                          child: const Text('Lokale Kopie löschen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}
