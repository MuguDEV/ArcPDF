import 'dart:async';

import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets/arc_progress_indicator.dart';

import '../updater/updater_service.dart';
import 'log_viewer_screen.dart';
import 'settings_controller.dart';
import 'about_screen.dart';
import '../security/security_settings_section.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/theme/arc_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = 'Loading...';
  bool _checkingForUpdates = false;
  DialogRoute<void>? _updateLoadingRoute;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      if (mounted) setState(() => _version = 'Version unavailable');
    }
  }

  @override
  void dispose() {
    final loading = _updateLoadingRoute;
    _updateLoadingRoute = null;
    // Disposal can occur while the Navigator is updating its route stack.
    scheduleMicrotask(() {
      if (loading?.isActive == true && loading?.navigator?.mounted == true) {
        loading!.navigator!.removeRoute(loading);
      }
    });
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (!mounted || _checkingForUpdates) return;
    final client = ref.read(updaterHttpClientProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    final owner = ModalRoute.of(context);
    final loading = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: ArcProgressIndicator()),
      ),
    );
    setState(() => _checkingForUpdates = true);
    _updateLoadingRoute = loading;
    unawaited(navigator.push(loading));
    try {
      final result = await UpdaterService.checkForUpdateResult(client: client);
      final wasCurrent = loading.isCurrent;
      if (loading.isActive && navigator.mounted) navigator.removeRoute(loading);
      _updateLoadingRoute = null;
      if (!mounted || !wasCurrent || owner?.isCurrent == false) return;
      switch (result.status) {
        case UpdateCheckStatus.updateAvailable:
          _showUpdateDialog(result.release!);
        case UpdateCheckStatus.upToDate:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are on the latest version!')),
          );
        case UpdateCheckStatus.unavailable:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not check for updates. Check your connection and try again.'),
          ));
        case UpdateCheckStatus.failure:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not read update information. Please try again later.'),
          ));
      }
    } finally {
      if (loading.isActive && navigator.mounted) navigator.removeRoute(loading);
      _updateLoadingRoute = null;
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  void _showUpdateDialog(GitHubRelease release) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    HugeIcons.strokeRoundedPackageOpen,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Update Available',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  release.version,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5)),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: MarkdownBody(
                        data: release.body,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium,
                          h1: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          h2: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          h3: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          listBullet: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final route = ModalRoute.of(context);
                        final navigator = Navigator.of(context);
                        var opened = false;
                        try {
                          opened = await launchUrl(Uri.parse(release.url),
                              mode: LaunchMode.externalApplication);
                        } catch (_) {
                          // Keep the release dialog available for another attempt.
                        }
                        if (!context.mounted) return;
                        if (opened) {
                          if (route != null &&
                              route.isActive &&
                              navigator.mounted) {
                            navigator.removeRoute(route);
                          }
                        } else if (messenger.mounted) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(
                                'Could not open the download page. Please try again.'),
                          ));
                        }
                      },
                      icon: const Icon(HugeIcons.strokeRoundedDownload04,
                          size: 20),
                      label: const Text('Download'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        const GlassSliverAppBar(
          title:
              Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              // ── Appearance ───────────────────────────────────
              const _SectionHeader(label: 'Appearance')
                  .animate()
                  .fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Text('Theme Mode',
                          style: theme.textTheme.titleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System',
                                  maxLines: 1, overflow: TextOverflow.visible),
                              icon: Icon(Icons.brightness_auto_rounded)),
                          ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light',
                                  maxLines: 1, overflow: TextOverflow.visible),
                              icon: Icon(Icons.light_mode_rounded)),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark',
                                  maxLines: 1, overflow: TextOverflow.visible),
                              icon: Icon(Icons.dark_mode_rounded)),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) => ctrl.setThemeMode(s.first),
                        style: ButtonStyle(
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28)),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Typography',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppFontFamily.values.map((f) {
                              final selected = settings.fontFamily == f;
                              return FilterChip(
                                label: Text(f.displayName),
                                labelStyle: const TextStyle(height: 1.0),
                                selected: selected,
                                showCheckmark: false,
                                onSelected: (_) => ctrl.setFontFamily(f),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
                  .animate(delay: 40.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Layout ───────────────────────────────────────
              const _SectionHeader(label: 'Layout & Appearance')
                  .animate(delay: 120.ms)
                  .fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: settings.useBlurEffect,
                      onChanged: ctrl.setUseBlurEffect,
                      title: const Text('Frosted Glass (Blur)'),
                      subtitle: const Text(
                          'Enable standard blur effects on UI elements'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile.adaptive(
                      value: settings.useLiquidGlass,
                      onChanged: settings.useBlurEffect
                          ? ctrl.setUseLiquidGlass
                          : null,
                      title: const Text('Apple Liquid Glass'),
                      subtitle: const Text(
                          'Premium iOS-style highly polished glass effect'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile.adaptive(
                      value: settings.useHaptics,
                      onChanged: ctrl.setUseHaptics,
                      title: const Text('Haptic Feedback'),
                      subtitle: const Text('Vibrate on taps and interactions'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile.adaptive(
                      value: settings.keepScreenAwake,
                      onChanged: (val) {
                        ctrl.setKeepScreenAwake(val);
                        WakelockPlus.toggle(enable: val);
                      },
                      title: const Text('Keep Screen Awake'),
                      subtitle: const Text('Prevent screen from turning off'),
                    ),
                  ],
                ),
              )
                  .animate(delay: 140.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Security ──────────────────────────────────────
              const _SectionHeader(label: 'Security')
                  .animate(delay: 150.ms)
                  .fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              const SecuritySettingsSection()
                  .animate(delay: 155.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Performance & Tuning ──────────────────────────
              const _SectionHeader(label: 'Performance & Tuning')
                  .animate(delay: 160.ms)
                  .fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      value: settings.lowPowerMode,
                      onChanged: ctrl.setLowPowerMode,
                      title: const Text('Eco Mode / Low Power'),
                      subtitle: const Text(
                          'Disables blur, 120Hz, animations, and lowers thumbnail quality to save battery and memory.'),
                      activeTrackColor: theme.colorScheme.primary,
                      secondary: Icon(HugeIcons.strokeRoundedBatteryLow,
                          color: settings.lowPowerMode
                              ? theme.colorScheme.primary
                              : null),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile.adaptive(
                      value: settings.enableGyroCards,
                      onChanged: ctrl.setEnableGyroCards,
                      title: const Text('3D Gyroscope Cards'),
                      subtitle: const Text(
                          'Cards physically tilt with your device sensors.'),
                      activeTrackColor: theme.colorScheme.primary,
                      secondary: Icon(Icons.screen_rotation_rounded,
                          color: settings.enableGyroCards
                              ? theme.colorScheme.primary
                              : null),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile.adaptive(
                      value: settings.enableMeshBackground,
                      onChanged: ctrl.setEnableMeshBackground,
                      title: const Text('Animated Mesh Background'),
                      subtitle: const Text(
                          'Adds a slowly shifting liquid aura background to the Home screen.'),
                      activeTrackColor: theme.colorScheme.primary,
                      secondary: Icon(HugeIcons.strokeRoundedLayers01,
                          color: settings.enableMeshBackground
                              ? theme.colorScheme.primary
                              : null),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _SliderSetting(
                      title: 'Animation intensity',
                      valueLabel:
                          '${(settings.animationIntensity * 100).round()}%',
                      value: settings.animationIntensity,
                      min: 0.01,
                      max: 1,
                      onChanged: ctrl.setAnimationIntensity,
                    ),
                    _SliderSetting(
                      title: 'Animation speed',
                      valueLabel:
                          '${settings.animationSpeed.toStringAsFixed(1)}x',
                      value: settings.animationSpeed,
                      min: 0.5,
                      max: 2,
                      divisions: 15,
                      onChanged: ctrl.setAnimationSpeed,
                    ),
                    _SliderSetting(
                      title: 'Thumbnail quality',
                      valueLabel:
                          '${(settings.thumbnailQuality * 100).round()}%',
                      value: settings.thumbnailQuality,
                      min: 0.01,
                      max: 1,
                      onChanged: ctrl.setThumbnailQuality,
                    ),
                    _SliderSetting(
                      title: 'Compression workers',
                      valueLabel:
                          '${settings.compressionThreads} image encoding workers',
                      value: settings.compressionThreads.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      onChanged: (value) =>
                          ctrl.setCompressionThreads(value.toInt()),
                    ),
                  ],
                ),
              )
                  .animate(delay: 180.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Diagnostics ──────────────────────────────────
              const _SectionHeader(label: 'Diagnostics')
                  .animate(delay: 190.ms)
                  .fadeIn(duration: 260.ms),
              const SizedBox(height: 8),

              _SettingsCard(
                child: ListTile(
                  leading: const Icon(Icons.bug_report_rounded),
                  title: const Text('View Logs'),
                  subtitle: const Text('Check app diagnostics and errors'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (context) => const LogViewerScreen()),
                    );
                  },
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── About ────────────────────────────────────────
              _SettingsCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius:
                              BorderRadius.circular(ArcColors.cardRadius),
                        ),
                        child:
                            const Icon(HugeIcons.strokeRoundedPdf02, size: 22),
                      ),
                      title: const Text('ArcPDF'),
                      subtitle: Text('$_version · Your local PDF workspace'),
                      trailing: const Icon(Icons.info_outline_rounded),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AboutScreen()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.system_update_rounded),
                      title: const Text('Check for Updates'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _checkingForUpdates ? null : _checkForUpdates,
                    ),
                  ],
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),

              const SizedBox(height: 20),
            ],
          ),
        ),
        const SliverSafeArea(
          minimum: EdgeInsets.only(bottom: 140),
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

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(valueLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          Semantics(
            label: title,
            child: Slider.adaptive(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              semanticFormatterCallback: (_) => valueLabel,
            ),
          ),
        ],
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
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
