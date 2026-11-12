import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'strings.dart';

/// Navigation rail on wide windows, bottom bar on phones.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final destinations = [
      (Icons.home_outlined, Icons.home_rounded, s.navHome),
      (Icons.search_rounded, Icons.search_rounded, s.navSearch),
      (Icons.download_for_offline_outlined, Icons.download_for_offline_rounded, s.navDownloaded),
      (Icons.settings_outlined, Icons.settings_rounded, s.navSettings),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      const HomeScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      const SettingsScreen(),
    ];
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
