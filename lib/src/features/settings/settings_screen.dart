import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        const SliverAppBar(
          pinned: true,
          title: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              // ── Appearance ───────────────────────────────────
              _SectionHeader(label: 'Appearance').animate().fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text('Theme Mode', style: theme.textTheme.titleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) => ctrl.setThemeMode(s.first),
                        style: ButtonStyle(
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Typography', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppFontFamily.values.map((f) {
                              final selected = settings.fontFamily == f;
                              return FilterChip(
                                label: Text(f.displayName),
                                selected: selected,
                                showCheckmark: false,
                                onSelected: (_) => ctrl.setFontFamily(f),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    SwitchListTile.adaptive(
                      value: settings.useDynamicColor,
                      onChanged: ctrl.setDynamicColor,
                      title: const Text('Material You colors'),
                      subtitle: const Text('Use wallpaper-based color extraction'),
                    ),
                  ],
                ),
              ).animate(delay: 40.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Layout ───────────────────────────────────────
              _SectionHeader(label: 'Layout').animate(delay: 120.ms).fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: SwitchListTile.adaptive(
                  value: settings.useGrid,
                  onChanged: ctrl.setGrid,
                  title: const Text('Grid layout'),
                  subtitle: const Text('Show PDFs in a masonry grid instead of a list'),
                ),
              ).animate(delay: 140.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Reader ───────────────────────────────────────
              _SectionHeader(label: 'Reader').animate(delay: 160.ms).fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: const Text('Animation intensity'),
                      subtitle: Text('${(settings.animationIntensity * 100).round()}%'),
                      trailing: SizedBox(
                        width: 160,
                        child: Slider.adaptive(
                          value: settings.animationIntensity,
                          min: 0.4,
                          max: 1.4,
                          onChanged: ctrl.setAnimationIntensity,
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Thumbnail quality'),
                      subtitle: Text('${(settings.thumbnailQuality * 100).round()}%'),
                      trailing: SizedBox(
                        width: 160,
                        child: Slider.adaptive(
                          value: settings.thumbnailQuality,
                          min: 0.5,
                          max: 1.0,
                          onChanged: ctrl.setThumbnailQuality,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 180.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── About ────────────────────────────────────────
              _SettingsCard(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                  ),
                  title: const Text('ArcPDF'),
                  subtitle: const Text('v1.0.0 · Your local PDF workspace'),
                ),
              ).animate(delay: 200.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),
            ],
          ),
        ),
        const SliverSafeArea(
          minimum: EdgeInsets.only(bottom: 120),
          sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
