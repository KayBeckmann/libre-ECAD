import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/company_users_api.dart';
import '../session_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionService>().changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
        confirmPassword: _confirm.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwort geändert. Bitte erneut anmelden.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Backend nicht erreichbar. Bitte erneut versuchen.',
        );
      }
    } finally {
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Einstellungen')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Passwort ändern',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nach der Änderung werden alle Sitzungen beendet. Bitte erneut anmelden.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _current,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Aktuelles Passwort',
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Aktuelles Passwort eingeben.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _next,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Neues Passwort',
                    ),
                    validator: (value) =>
                        value == null || value.length < 8 || value.length > 1024
                        ? 'Mindestens 8 Zeichen erforderlich (maximal 1024).'
                        : value == _current.text
                        ? 'Neues Passwort muss sich unterscheiden.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Neues Passwort bestätigen',
                    ),
                    validator: (value) => value != _next.text
                        ? 'Passwörter stimmen nicht überein.'
                        : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Bitte warten…' : 'Passwort ändern'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
