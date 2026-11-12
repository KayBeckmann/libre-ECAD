import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'models.dart';
import 'offline/offline_screen.dart';
import 'screens/articles_screen.dart';
import 'screens/contributions_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/settings_screen.dart';
import 'session_service.dart';

/// Ein Bereich der Arbeitsplatz-Navigation. Jeder Bereich hat seinen
/// eigenen verschachtelten `Navigator`, damit Detailseiten (Projekt,
/// Schaltplan, Artikel …) innerhalb des Bereichs geöffnet werden und
/// die Seitenleiste dabei sichtbar bleibt.
class WorkspaceSection {
  const WorkspaceSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
  final String label;
  final IconData icon, selectedIcon;
  final WidgetBuilder builder;
}

List<WorkspaceSection> workspaceSections(Session session) => [
  WorkspaceSection(
    label: 'Arbeitsplatz',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    builder: (_) => const HomeScreen(),
  ),
  WorkspaceSection(
    label: 'Projekte',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    builder: (_) => ProjectsScreen(session: session),
  ),
  WorkspaceSection(
    label: 'Artikelbibliothek',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    builder: (_) => ArticlesScreen(session: session),
  ),
  WorkspaceSection(
    label: 'Katalogbeiträge',
    icon: Icons.public_outlined,
    selectedIcon: Icons.public,
    builder: (_) => ContributionsScreen(session: session),
  ),
  if (!kIsWeb)
    WorkspaceSection(
      label: 'Offlineprojekte',
      icon: Icons.offline_bolt_outlined,
      selectedIcon: Icons.offline_bolt,
      builder: (_) => const OfflineScreen(),
    ),
  WorkspaceSection(
    label: 'Einstellungen',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    builder: (_) => const SettingsScreen(),
  ),
];

/// Persistenter Rahmen nach der Anmeldung: Seitenleiste (breit), Rail
/// (mittel) oder untere Navigationsleiste (schmal) plus ein
/// `IndexedStack` verschachtelter Navigatoren. Bereiche werden erst
/// beim ersten Öffnen aufgebaut, damit kein Bereich im Hintergrund
/// Anfragen an das Backend stellt; einmal geöffnete Bereiche behalten
/// ihren Zustand (z. B. einen ungespeicherten Schaltplanentwurf).
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, this.initialSection = 0});
  final int initialSection;

  static const sidebarBreakpoint = 1400.0;
  static const railBreakpoint = 980.0;

  /// Wechselt den Bereich aus einer beliebigen Seite innerhalb der Shell.
  static void open(BuildContext context, int section) =>
      context.findAncestorStateOfType<_WorkspaceShellState>()?.select(section);

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  late int current = widget.initialSection;
  bool navigationHidden = false;
  final visited = <int>{};
  final keys = <int, GlobalKey<NavigatorState>>{};

  GlobalKey<NavigatorState> keyFor(int index) =>
      keys.putIfAbsent(index, GlobalKey<NavigatorState>.new);

  void select(int index) {
    if (index == current) {
      // Erneuter Klick auf den aktiven Bereich führt zu dessen Startseite.
      keyFor(index).currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => current = index);
  }

  Future<void> logout() async {
    await context.read<SessionService>().logout();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>().session;
    if (session == null) return const SizedBox.shrink();
    final sections = workspaceSections(session);
    if (current >= sections.length) current = 0;
    visited.add(current);
    final width = MediaQuery.sizeOf(context).width;
    final mode = width >= WorkspaceShell.sidebarBreakpoint
        ? _NavMode.sidebar
        : width >= WorkspaceShell.railBreakpoint
        ? _NavMode.rail
        : _NavMode.bottom;

    // Eigener Semantik-Container: Der `ModalBarrier` jeder Route im
    // verschachtelten Navigator blockiert sonst die Semantik aller zuvor
    // gezeichneten Geschwister, also der Seitenleiste bzw. Rail
    // (Screenreader und Browser-Abnahme sähen keine Navigation).
    final content = Semantics(
      container: true,
      explicitChildNodes: true,
      child: IndexedStack(
        index: current,
        children: [
          for (var i = 0; i < sections.length; i++)
            if (visited.contains(i))
              NavigatorPopHandler(
                enabled: i == current,
                onPopWithResult: (_) => keyFor(i).currentState?.maybePop(),
                child: Navigator(
                  key: keyFor(i),
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    settings: settings,
                    builder: sections[i].builder,
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
        ],
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          if (mode != _NavMode.bottom)
            SizedBox(
              width: 48,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: IconButton(
                    tooltip: navigationHidden
                        ? 'Menüleiste einblenden'
                        : 'Menüleiste ausblenden',
                    onPressed: () => setState(
                      () => navigationHidden = !navigationHidden,
                    ),
                    icon: Icon(
                      navigationHidden ? Icons.menu_open : Icons.menu,
                    ),
                  ),
                ),
              ),
            ),
          if (!navigationHidden && mode == _NavMode.sidebar)
            _Sidebar(
              sections: sections,
              current: current,
              session: session,
              onSelect: select,
              onLogout: logout,
            )
          else if (!navigationHidden && mode == _NavMode.rail)
            _Rail(
              sections: sections,
              current: current,
              onSelect: select,
              onLogout: logout,
            ),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: mode == _NavMode.bottom
          ? NavigationBar(
              selectedIndex: current,
              onDestinationSelected: select,
              labelBehavior: sections.length > 5
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final s in sections)
                  NavigationDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.selectedIcon),
                    label: s.label,
                  ),
              ],
            )
          : null,
    );
  }
}

enum _NavMode { sidebar, rail, bottom }

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final mark = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: ecadGold),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.electrical_services, color: ecadGold),
    );
    if (compact) return Tooltip(message: 'LibreECAD', child: mark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            mark,
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'LibreECAD',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'ELEKTROPLANUNG',
            style: TextStyle(color: ecadMuted, fontSize: 11, letterSpacing: 2),
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.current,
    required this.session,
    required this.onSelect,
    required this.onLogout,
  });
  final List<WorkspaceSection> sections;
  final int current;
  final Session session;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final roleLabel = session.role == UserRole.admin
        ? 'Firmenadmin'
        : 'Zeichner';
    return Container(
      width: 236,
      color: ecadPanel,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: 32),
          for (var i = 0; i < sections.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: i == current ? ecadSelected : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  selected: i == current,
                  leading: Icon(
                    i == current ? sections[i].selectedIcon : sections[i].icon,
                  ),
                  title: Text(sections[i].label),
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: ecadSelected,
                child: Text(
                  session.username.isEmpty
                      ? '?'
                      : session.username[0].toUpperCase(),
                  style: const TextStyle(color: ecadGold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$roleLabel · ${session.companyName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ecadMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Abmelden',
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.sections,
    required this.current,
    required this.onSelect,
    required this.onLogout,
  });
  final List<WorkspaceSection> sections;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => NavigationRail(
    backgroundColor: ecadPanel,
    selectedIndex: current,
    onDestinationSelected: onSelect,
    labelType: NavigationRailLabelType.all,
    leading: const Padding(
      padding: EdgeInsets.only(top: 8, bottom: 16),
      child: _Brand(compact: true),
    ),
    trailing: Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: IconButton(
            tooltip: 'Abmelden',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ),
      ),
    ),
    destinations: [
      for (final s in sections)
        NavigationRailDestination(
          icon: Icon(s.icon),
          selectedIcon: Icon(s.selectedIcon),
          label: Text(s.label, textAlign: TextAlign.center),
        ),
    ],
  );
}
