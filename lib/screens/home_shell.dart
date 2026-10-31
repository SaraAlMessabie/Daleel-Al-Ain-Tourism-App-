import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../map_module/al_ain_map_module.dart';
import 'browse_screen.dart';
import 'camera_screen.dart';
import 'detail_screen.dart';
import 'profile_screen.dart';

/// The four bottom tabs: Explore, Map (with buses), Camera, Profile.
/// The Assistant tab returns here once it actually works; a "coming soon"
/// page should not take a main navigation slot.
/// Tabs are built the first time they are opened (saves RAM at start-up).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = Tabs.explore;
  final Set<int> _opened = {Tabs.explore};

  Widget _page(int i, AppState s) {
    if (!_opened.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case Tabs.explore:
        return const BrowseScreen();
      case Tabs.map:
        return AlAinMapScreen(
          themeMode: ThemeMode.light, // Daleel is light-only for now
          isArabic: s.language == 'ar', // the app language also controls the map
          focusAttractionId: s.mapFocusId,
          focusNonce: s.mapFocusNonce,
          focusDirections: s.mapFocusDirections,
          favoriteIds: s.favoriteIds,
          onToggleFavorite: s.toggleFavorite,
          onOpenDetails: (id) => DetailScreen.openById(context, id),
        );
      case Tabs.camera:
        return const CameraScreen();
      default:
        return const ProfileScreen();
    }
  }

  void _select(int i) => setState(() {
        _i = i;
        _opened.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = s.t;

    // "Show on map" / "Directions" asked us to switch tab.
    final req = s.tabRequest;
    if (req != null) {
      s.clearTabRequest();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(req);
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: [for (var i = 0; i < 4; i++) _page(i, s)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: _select,
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore),
              label: t('tab_browse')),
          NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: t('tab_map')),
          NavigationDestination(
              icon: const Icon(Icons.photo_camera_outlined),
              selectedIcon: const Icon(Icons.photo_camera),
              label: t('tab_camera')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: t('tab_profile')),
        ],
      ),
    );
  }
}
