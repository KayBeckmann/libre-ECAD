import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/screens/login_screen.dart';
import 'src/session_service.dart';

void main() {
  runApp(const LibreEcadApp());
}

class LibreEcadApp extends StatelessWidget {
  const LibreEcadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionService(),
      child: MaterialApp(
        title: 'LibreECAD',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const LoginScreen(),
      ),
    );
  }
}
