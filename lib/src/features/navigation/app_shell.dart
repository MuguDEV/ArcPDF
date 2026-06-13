import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pdf/favorites/favorites_screen.dart';
import '../pdf/home/home_screen.dart';
import '../pdf/recent/recent_screen.dart';
import '../settings/settings_screen.dart';
import '../tools/tools_screen.dart';
import '../splash/splash_screen.dart';
import 'navigation_controller.dart';
import 'arc_nav_bar.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationControllerProvider);
    final doneSplash = ref.watch(splashDoneProvider);

    if (!doneSplash) return const SplashScreen();

    return Scaffold(
      body: Stack(
        children: [
          _buildOffstage(0, nav.index, const HomeScreen()),
          _buildOffstage(1, nav.index, const FavoritesScreen()),
          _buildOffstage(2, nav.index, const RecentScreen()),
          _buildOffstage(3, nav.index, const ToolsScreen()),
          _buildOffstage(4, nav.index, const SettingsScreen()),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: ArcNavBar(selectedIndex: nav.index),
    );
  }

  Widget _buildOffstage(int tabIndex, int currentIndex, Widget child) {
    final isSelected = tabIndex == currentIndex;
    return Offstage(
      offstage: !isSelected,
      child: AnimatedOpacity(
        opacity: isSelected ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastLinearToSlowEaseIn,
        child: child,
      ),
    );
  }
}
