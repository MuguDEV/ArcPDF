import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../pdf/favorites/favorites_screen.dart';
import '../pdf/home/home_screen.dart';
import '../pdf/recent/recent_screen.dart';
import '../settings/settings_screen.dart';
import '../splash/splash_screen.dart';
import 'navigation_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationControllerProvider);
    final doneSplash = ref.watch(splashDoneProvider);

    if (!doneSplash) return const SplashScreen();

    return Scaffold(
      // IndexedStack preserves all tab states + scroll positions
      body: Stack(
        children: [
          _buildOffstage(0, nav.index, const HomeScreen()),
          _buildOffstage(1, nav.index, const FavoritesScreen()),
          _buildOffstage(2, nav.index, const RecentScreen()),
          _buildOffstage(3, nav.index, const SettingsScreen()),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: _ArcNavBar(selectedIndex: nav.index),
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

class _ArcNavBar extends ConsumerWidget {
  const _ArcNavBar({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Charcoal surface — never pure black
    final navBg = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFFCFCFC);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(40, 0, 40, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: navBg.withValues(alpha: isDark ? 0.75 : 0.85),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedIndex: selectedIndex,
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              indicatorColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : theme.colorScheme.primary.withValues(alpha: 0.08),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              destinations: [
                _buildDest(HugeIcons.strokeRoundedHome01, 'Home', 0, isDark, theme),
                _buildDest(HugeIcons.strokeRoundedFavourite, 'Favorites', 1, isDark, theme),
                _buildDest(HugeIcons.strokeRoundedClock01, 'Recent', 2, isDark, theme),
                _buildDest(HugeIcons.strokeRoundedSettings01, 'Settings', 3, isDark, theme),
              ],
              onDestinationSelected: (i) {
                if (i != selectedIndex) {
                  HapticFeedback.selectionClick();
                  ref.read(navigationControllerProvider.notifier).setIndex(i);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  NavigationDestination _buildDest(IconData icon, String label, int index, bool isDark, ThemeData theme) {
    final isSelected = selectedIndex == index;
    final color = isSelected 
        ? (isDark ? Colors.white : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return NavigationDestination(
      icon: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Icon(icon, color: color, size: 24),
      ),
      label: label,
    );
  }
}
