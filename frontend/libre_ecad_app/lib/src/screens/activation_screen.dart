import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session_service.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.backendUrl});
  final String backendUrl;
  @override
  State<ActivationScreen> createState() => _ActivationState();
}

class _ActivationState extends State<ActivationScreen> {
  final token = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    token.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> submitActivation() async {
    if (password.text.length < 8 || password.text != repeat.text) {
      setState(
        () => error =
            'Mindestens 8 Zeichen; beide Passwörter müssen übereinstimmen.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context
          .read<SessionService>()
          .companyUsersApiFor(Uri.parse(widget.backendUrl))
          .activate(token: token.text.trim(), password: password.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Zugang aktiviert. Jetzt mit deinem Benutzernamen anmelden.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Zugang aktivieren')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text('Ziel-Backend: ${widget.backendUrl}'),
            const SizedBox(height: 12),
            const Text(
              'Den einmaligen Token erhältst du von deinem Admin. Hier legst du dein eigenes Passwort fest.',
            ),
            TextField(
              controller: token,
              decoration: const InputDecoration(labelText: 'Aktivierungstoken'),
              autocorrect: false,
              obscureText: true,
            ),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Neues Passwort'),
              obscureText: true,
            ),
            TextField(
              controller: repeat,
              decoration: const InputDecoration(
                labelText: 'Passwort wiederholen',
              ),
              obscureText: true,
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : submitActivation,
              child: Text(busy ? 'Wird aktiviert …' : 'Aktivieren'),
            ),
          ],
        ),
      ),
    ),
  );
}
