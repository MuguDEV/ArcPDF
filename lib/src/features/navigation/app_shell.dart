import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../onboarding/onboarding_controller.dart';
import '../onboarding/onboarding_screen.dart';
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
    // First run only; see OnboardingCompletedNotifier for the skip rules.
    if (!ref.watch(onboardingCompletedProvider)) {
      return const OnboardingScreen();
    }

    return Scaffold(
      body: Builder(builder: (context) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          // The outer scaffold owns the dock and bottom system inset.
          data: media.copyWith(
            viewPadding: media.viewPadding.copyWith(
              bottom: media.padding.bottom,
            ),
          ),
          child: Stack(
            children: [
              _screenForIndex(nav.index),
            ],
          ),
        );
      }),
      // Let each screen continue behind the transparent area surrounding the
      // dock. Scaffold still contributes the dock height to MediaQuery so the
      // final list item and floating actions can clear it safely.
      extendBody: true,
      bottomNavigationBar: ArcNavBar(selectedIndex: nav.index),
    );
  }

  Widget _screenForIndex(int index) {
    return switch (index) {
      1 => const FavoritesScreen(),
      2 => const RecentScreen(),
      3 => const ToolsScreen(),
      4 => const SettingsScreen(),
      _ => const HomeScreen(),
    };
  }
}
