import 'package:flutter/material.dart';

const ecadGold = Color(0xffeab75a);
const ecadMuted = Color(0xffa8bec1);
ThemeData ecadTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ecadGold,
        brightness: Brightness.dark,
      ).copyWith(
        primary: ecadGold,
        onPrimary: const Color(0xff071923),
        secondary: const Color(0xff66c5ba),
        surface: const Color(0xff102631),
        onSurface: const Color(0xffe8f1ef),
        outline: const Color(0xff31505a),
        error: const Color(0xffed8e80),
      );
  return ThemeData(
    useMaterial3: true,
    fontFamilyFallback: const ['EcadSymbols'],
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xff071923),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xff0b202a),
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xff102631),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xff31505a)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff0b202a),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xff31505a)),
  );
}

class EcadShell extends StatelessWidget {
  const EcadShell({
    super.key,
    required this.title,
    required this.child,
    this.navigation = const [],
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> navigation, actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final wide = size.maxWidth >= 980;
      final sidebar = Container(
        width: 236,
        color: const Color(0xff0b202a),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: ecadGold),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.electrical_services, color: ecadGold),
                ),
                const SizedBox(width: 12),
                const Text(
                  'LibreECAD',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 38),
              child: Text(
                'ELEKTROPLANUNG',
                style: TextStyle(
                  color: ecadMuted,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
            ),
            ...navigation.map(
              (tile) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: tile is ListTile && tile.selected
                      ? const Color(0xff23434c)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: tile,
                ),
              ),
            ),
            const Spacer(),
            const Divider(),
            const Text(
              'Ihr Projekt. Ihr Backend.',
              style: TextStyle(color: ecadGold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Schaltpläne und Projektdaten in Ihrem Firmenkontext.',
              style: TextStyle(color: ecadMuted, height: 1.6),
            ),
          ],
        ),
      );
      return Scaffold(
        drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
        appBar: wide ? null : AppBar(title: Text(title), actions: actions),
        body: Row(
          children: [
            if (wide) sidebar,
            Expanded(
              child: Column(
                children: [
                  if (wide)
                    Container(
                      height: 78,
                      padding: const EdgeInsets.symmetric(horizontal: 38),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xff31505a)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Arbeitsplatz',
                            style: TextStyle(color: ecadMuted),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('/'),
                          ),
                          Expanded(child: Text(title)),
                          ...actions,
                        ],
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
