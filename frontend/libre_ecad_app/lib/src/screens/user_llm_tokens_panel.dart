import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/company_users_api.dart';
import '../session_service.dart';

/// Personal API keys are managed by an interactive login in Einstellungen.
/// Their raw value stays only in the one-time creation dialog.
class UserLlmTokensPanel extends StatefulWidget {
  const UserLlmTokensPanel({super.key});

  @override
  State<UserLlmTokensPanel> createState() => _UserLlmTokensPanelState();
}

class _UserLlmTokensPanelState extends State<UserLlmTokensPanel> {
  List<Map<String, Object?>> _tokens = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'LLM-Zugänge konnten nicht geladen werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final service = context.read<SessionService>();
    final session = service.session;
    if (session == null) return;
    final result = await service
        .companyUsersApiFor(session.backendUrl)
        .listUserLlmTokens(session.token);
    if (mounted) setState(() => _tokens = result);
  }

  Future<void> _load() => _run(_refresh);

  Future<void> _create() async {
    final label = TextEditingController();
    var consent = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Persönlichen LLM-Zugang erstellen'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Dieser Zugang hat dieselben aktuellen Rechte wie dein Benutzer – '
                    'auch für künftig für dich sichtbare Projekte und Schreibaktionen. '
                    'Wer den Token besitzt, kann in deinem Namen handeln. '
                    'Nur einem vertrauenswürdigen LLM-Client geben; '
                    'Projektzugänge mit begrenztem Umfang bleiben separat verfügbar.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: label,
                    maxLength: 100,
                    onChanged: (_) => update(() {}),
                    decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  ),
                  CheckboxListTile(
                    value: consent,
                    onChanged: (value) =>
                        update(() => consent = value ?? false),
                    title: const Text(
                      'Vollen Zugriff in meinem Namen bewusst erlauben',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: consent && label.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialog, true)
                  : null,
              child: const Text('Zugang erstellen'),
            ),
          ],
        ),
      ),
    );
    final name = label.text.trim();
    Future.delayed(const Duration(milliseconds: 350), label.dispose);
    if (accepted != true || !mounted) return;
    await _run(() async {
      final service = context.read<SessionService>();
      final session = service.session!;
      final created = await service
          .companyUsersApiFor(session.backendUrl)
          .createUserLlmToken(session.token, label: name);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Token einmalig kopieren'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Der Klartext wird nach dem Schließen nicht erneut angezeigt. '
                  'Sicher im LLM-Client verwahren; nicht in Chats oder Projekten ablegen.',
                ),
                const SizedBox(height: 16),
                SelectableText(created['token'] as String),
                const SizedBox(height: 16),
                SelectableText(
                  'ECAD_BACKEND_URL=${session.backendUrl}\n'
                  'Gültig bis ${created['expiresAt']}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      if (mounted) await _refresh();
    });
  }

  Future<void> _revoke(String id) => _run(() async {
    final service = context.read<SessionService>();
    final session = service.session!;
    await service
        .companyUsersApiFor(session.backendUrl)
        .revokeUserLlmToken(session.token, id);
    if (mounted) await _refresh();
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 40),
      Text(
        'LLM-Zugang für alle meine Projekte',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        'Gilt mit deinen jeweils aktuellen Benutzerrechten für alle '
        'für dich sichtbaren Projekte. Für begrenzte Freigaben weiterhin '
        'einen Projektzugang im Projekt erstellen.',
      ),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.key),
          label: const Text('LLM-Zugang erstellen'),
        ),
      ),
      if (_tokens.isEmpty && !_busy)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('Noch kein persönlicher LLM-Zugang.'),
        ),
      for (final token in _tokens)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(token['label'] as String),
          subtitle: Text('Gültig bis ${token['expiresAt']}'),
          trailing: token['revoked'] == true
              ? const Text('Widerrufen')
              : TextButton(
                  onPressed: _busy
                      ? null
                      : () => _revoke(token['id'] as String),
                  child: const Text('Widerrufen'),
                ),
        ),
    ],
  );
}
