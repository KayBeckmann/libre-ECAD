import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/company_users_api.dart';
import '../session_service.dart';
import 'home_screen.dart';

/// M1.4 — "Web-/App-Anmeldeansicht mit vorbelegtem Kay-Managed-Backend
/// und sichtbarer Möglichkeit, ein Self-hosted-/Dienstleister-Backend
/// auszuwählen." Zeigt vor der Eingabe von Zugangsdaten, welches
/// Backend/welcher Zielserver gewählt ist.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _backendUrlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _showBackendField = false;

  @override
  void initState() {
    super.initState();
    _loadBackendUrl();
  }

  Future<void> _loadBackendUrl() async {
    final url = await context.read<SessionService>().loadBackendUrl();
    if (mounted) setState(() => _backendUrlCtrl.text = url);
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionService>().login(
            backendUrl: _backendUrlCtrl.text.trim(),
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Backend nicht erreichbar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('LibreECAD', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Ziel-Backend: ${_backendUrlCtrl.text.isEmpty ? '…' : _backendUrlCtrl.text}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: () => setState(() => _showBackendField = !_showBackendField),
                  child: Text(_showBackendField ? 'Backend ausblenden' : 'Anderes Backend wählen'),
                ),
                if (_showBackendField)
                  TextField(
                    controller: _backendUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Backend-URL',
                      helperText: 'Self-hosted oder Dienstleister-Backend statt Kays Managed-Backend.',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Benutzername'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Passwort'),
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Anmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
