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
import 'haptic_service.dart';
import 'about_screen.dart';
import '../security/security_settings_section.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/theme/arc_colors.dart';
import '../../shared/theme/arc_theme.dart';
import '../backup/backup_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = 'Loading...';
  bool _checkingForUpdates = false;
  DialogRoute<void>? _updateLoadingRoute;
  final _search = TextEditingController();
  String _query = '';

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
    _search.dispose();
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

  List<String> get _tokens => _query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();

  void _setQuery(String value) => setState(() => _query = value);

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  List<_Group> _groups(
    BuildContext context,
    AppSettings settings,
    SettingsController ctrl,
    ThemeData theme,
  ) {
    final colors = theme.colorScheme;
    return [
      _Group(
        id: 'appearance',
        title: 'Appearance',
        entries: [
          _Entry(
            title: 'Theme Mode',
            keywords: 'theme dark light system night day',
            child: _ChoiceBlock(
              title: 'Theme Mode',
              child: _SettingsChoices<ThemeMode>(
                options: const [
                  _Choice(
                      value: ThemeMode.system,
                      label: 'System',
                      icon: Icons.brightness_auto_rounded),
                  _Choice(
                      value: ThemeMode.light,
                      label: 'Light',
                      icon: Icons.light_mode_rounded),
                  _Choice(
                      value: ThemeMode.dark,
                      label: 'Dark',
                      icon: Icons.dark_mode_rounded),
                ],
                selected: settings.themeMode,
                onSelected: ctrl.setThemeMode,
              ),
            ),
          ),
          _Entry(
            title: 'Typography',
            keywords: 'font typeface text family inter roboto nunito jakarta',
            child: _ChoiceBlock(
              title: 'Typography',
              child: _SettingsChoices<AppFontFamily>(
                options: AppFontFamily.values
                    .map(
                        (font) => _Choice(value: font, label: font.displayName))
                    .toList(),
                selected: settings.fontFamily,
                onSelected: ctrl.setFontFamily,
              ),
            ),
          ),
          _Entry(
            title: 'Accent color',
            keywords: 'accent colour color tint highlight muted',
            child: _ChoiceBlock(
              title: 'Accent color',
              description:
                  'Optional. Only buttons, switches and selections use it; '
                  'surfaces stay black and white.',
              child: _SettingsChoices<ArcAccent>(
                balanceRows: true,
                options: ArcAccent.values
                    .map((accent) => _Choice(
                          value: accent,
                          label: accent.displayName,
                          icon: accent == ArcAccent.none
                              ? Icons.format_color_reset_rounded
                              : null,
                          swatch: accent.colorFor(theme.brightness),
                        ))
                    .toList(),
                selected: settings.accent,
                onSelected: ctrl.setAccent,
              ),
            ),
          ),
          _Entry(
            title: 'High contrast',
            keywords:
                'contrast accessibility outline black white bold visibility '
                'vision',
            child: _ChoiceBlock(
              title: 'High contrast',
              description: switch (settings.highContrast) {
                HighContrastMode.off => 'Always use the standard look.',
                HighContrastMode.on =>
                  'Pure black and white, strong outlines, opaque bars.',
                HighContrastMode.system => MediaQuery.highContrastOf(context)
                    ? 'Following your system setting, which is on.'
                    : 'Following your system setting, which is off.',
              },
              child: _SettingsChoices<HighContrastMode>(
                balanceRows: true,
                options: HighContrastMode.values
                    .map(
                        (mode) => _Choice(value: mode, label: mode.displayName))
                    .toList(),
                selected: settings.highContrast,
                onSelected: ctrl.setHighContrast,
              ),
            ),
          ),
          const _Entry(
            title: 'Text size preview',
            keywords: 'text size font scale large accessibility display zoom',
            child: _TextSizePreview(),
          ),
        ],
      ),
      _Group(
        id: 'layout',
        title: 'Layout & Appearance',
        entries: [
          _Entry(
            title: 'Performance preset',
            keywords: 'preset smooth balanced battery custom performance '
                'speed effects',
            child: _ChoiceBlock(
              title: 'Performance preset',
              description: settings.performancePreset.description,
              liveDescription: true,
              child: _SettingsChoices<PerformancePreset>(
                balanceRows: true,
                options: PerformancePreset.values
                    .map((preset) =>
                        _Choice(value: preset, label: preset.displayName))
                    .toList(),
                selected: settings.performancePreset,
                onSelected: ctrl.setPerformancePreset,
              ),
            ),
          ),
          _Entry(
            title: 'Frosted Glass (Blur)',
            keywords: 'blur glass frosted translucent effects',
            child: SwitchListTile.adaptive(
              value: settings.useBlurEffect,
              secondary: const Icon(Icons.blur_on_rounded),
              onChanged: ctrl.setUseBlurEffect,
              title: const Text('Frosted Glass (Blur)'),
              subtitle:
                  const Text('Enable standard blur effects on UI elements'),
            ),
          ),
          _Entry(
            title: 'Apple Liquid Glass',
            keywords: 'liquid glass ios premium effects',
            child: SwitchListTile.adaptive(
              value: settings.useLiquidGlass,
              secondary: const Icon(Icons.auto_awesome_rounded),
              onChanged: settings.useBlurEffect ? ctrl.setUseLiquidGlass : null,
              title: const Text('Apple Liquid Glass'),
              subtitle:
                  const Text('Premium iOS-style highly polished glass effect'),
            ),
          ),
          _Entry(
            title: 'Haptic Feedback',
            keywords: 'haptic vibration vibrate touch feedback',
            child: SwitchListTile.adaptive(
              value: settings.useHaptics,
              secondary: const Icon(Icons.vibration_rounded),
              onChanged: (enabled) async {
                final haptics = ref.read(hapticServiceProvider);
                await ctrl.setUseHaptics(enabled);
                if (mounted && enabled) await haptics.vibrate();
              },
              title: const Text('Haptic Feedback'),
              subtitle: const Text('Vibrate on taps and interactions'),
            ),
          ),
          _Entry(
            title: 'Keep Screen Awake',
            keywords: 'screen awake wake lock sleep timeout display',
            child: SwitchListTile.adaptive(
              value: settings.keepScreenAwake,
              secondary: const Icon(Icons.screen_lock_portrait_rounded),
              onChanged: (val) {
                ctrl.setKeepScreenAwake(val);
                WakelockPlus.toggle(enable: val);
              },
              title: const Text('Keep Screen Awake'),
              subtitle: const Text('Prevent screen from turning off'),
            ),
          ),
        ],
      ),
      const _Group(
        id: 'security',
        title: 'Security',
        standalone: SecuritySettingsSection(),
        standaloneKeywords: 'security app lock pin pattern biometric '
            'fingerprint face unlock password privacy resume',
      ),
      _Group(
        id: 'performance',
        title: 'Performance & Tuning',
        entries: [
          _Entry(
            title: 'Eco Mode / Low Power',
            keywords: 'eco low power battery save refresh rate 120hz',
            child: SwitchListTile.adaptive(
              value: settings.lowPowerMode,
              onChanged: ctrl.setLowPowerMode,
              title: const Text('Eco Mode / Low Power'),
              subtitle: const Text(
                  'Disables blur, 120Hz, animations, and lowers thumbnail quality to save battery and memory.'),
              activeTrackColor: colors.primary,
              secondary: Icon(HugeIcons.strokeRoundedBatteryLow,
                  color: settings.lowPowerMode ? colors.primary : null),
            ),
          ),
          _Entry(
            title: '3D Gyroscope Cards',
            keywords: 'gyro gyroscope tilt 3d cards sensors motion',
            child: SwitchListTile.adaptive(
              value: settings.enableGyroCards,
              onChanged: ctrl.setEnableGyroCards,
              title: const Text('3D Gyroscope Cards'),
              subtitle:
                  const Text('Cards physically tilt with your device sensors.'),
              activeTrackColor: colors.primary,
              secondary: Icon(Icons.screen_rotation_rounded,
                  color: settings.enableGyroCards ? colors.primary : null),
            ),
          ),
          _Entry(
            title: 'Animated Mesh Background',
            keywords: 'mesh background aura animated home liquid',
            child: SwitchListTile.adaptive(
              value: settings.enableMeshBackground,
              onChanged: ctrl.setEnableMeshBackground,
              title: const Text('Animated Mesh Background'),
              subtitle: const Text(
                  'Adds a slowly shifting liquid aura background to the Home screen.'),
              activeTrackColor: colors.primary,
              secondary: Icon(HugeIcons.strokeRoundedLayers01,
                  color: settings.enableMeshBackground ? colors.primary : null),
            ),
          ),
          _Entry(
            title: 'Animation intensity',
            keywords: 'animation intensity motion effects',
            child: _SliderSetting(
              title: 'Animation intensity',
              valueLabel: '${(settings.animationIntensity * 100).round()}%',
              value: settings.animationIntensity,
              min: 0.01,
              max: 1,
              onChanged: ctrl.setAnimationIntensity,
            ),
          ),
          _Entry(
            title: 'Animation speed',
            keywords: 'animation speed duration motion',
            child: _SliderSetting(
              title: 'Animation speed',
              valueLabel: '${settings.animationSpeed.toStringAsFixed(1)}x',
              value: settings.animationSpeed,
              min: 0.5,
              max: 2,
              divisions: 15,
              onChanged: ctrl.setAnimationSpeed,
            ),
          ),
          _Entry(
            title: 'Thumbnail quality',
            keywords: 'thumbnail quality preview image memory',
            child: _SliderSetting(
              title: 'Thumbnail quality',
              valueLabel: '${(settings.thumbnailQuality * 100).round()}%',
              value: settings.thumbnailQuality,
              min: 0.01,
              max: 1,
              onChanged: ctrl.setThumbnailQuality,
            ),
          ),
          _Entry(
            title: 'Compression workers',
            keywords: 'compression workers threads image encoding compress',
            child: _SliderSetting(
              title: 'Compression workers',
              valueLabel:
                  '${settings.compressionThreads} image encoding workers',
              value: settings.compressionThreads.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (value) => ctrl.setCompressionThreads(value.toInt()),
            ),
          ),
        ],
      ),
      _Group(
        id: 'data',
        title: 'Data & support',
        entries: [
          _Entry(
            title: 'Backup & Restore',
            keywords: 'backup restore export import save migrate data library',
            child: ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Backup & Restore'),
              subtitle: const Text('Save or restore your ArcPDF data'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showBackupRestoreSheet(context),
            ),
          ),
          _Entry(
            title: 'View Logs',
            keywords: 'logs diagnostics errors debug bug report support',
            child: ListTile(
              leading: const Icon(Icons.bug_report_rounded),
              title: const Text('View Logs'),
              subtitle: const Text('Open Diagnostics & Logs'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const LogViewerScreen()),
                );
              },
            ),
          ),
        ],
      ),
      _Group(
        id: 'about',
        title: 'About',
        entries: [
          _Entry(
            title: 'ArcPDF',
            keywords: 'about version info app licenses',
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(ArcColors.cardRadius),
                ),
                child: const Icon(HugeIcons.strokeRoundedPdf02, size: 22),
              ),
              title: const Text('ArcPDF'),
              subtitle: Text('$_version · Your local PDF workspace'),
              trailing: const Icon(Icons.info_outline_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
            ),
          ),
          _Entry(
            title: 'Check for Updates',
            keywords: 'update upgrade version release new',
            child: ListTile(
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('Check for Updates'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _checkingForUpdates ? null : _checkForUpdates,
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);
    final tokens = _tokens;

    final visible = <_Group>[];
    var matchCount = 0;
    for (final group in _groups(context, settings, ctrl, theme)) {
      final filtered = group.filtered(tokens);
      if (filtered == null) continue;
      visible.add(filtered);
      matchCount += filtered.rowCount;
    }

    return ListTileTheme.merge(
      dense: false,
      visualDensity: VisualDensity.standard,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: ArcColors.space16, vertical: ArcColors.space4),
      minTileHeight: ArcColors.minRowHeight,
      minVerticalPadding: ArcColors.space4,
      minLeadingWidth: 24,
      horizontalTitleGap: ArcColors.space12,
      titleTextStyle: theme.textTheme.bodyLarge,
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      child: IconTheme.merge(
        data: const IconThemeData(size: 24),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            const GlassSliverAppBar(
              title: Text('Settings',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _SearchField(
                  controller: _search,
                  hasText: _query.isNotEmpty,
                  onChanged: _setQuery,
                  onClear: _clearSearch,
                  resultLabel: _query.trim().isEmpty
                      ? null
                      : matchCount == 0
                          ? 'No settings found'
                          : matchCount == 1
                              ? '1 setting found'
                              : '$matchCount settings found',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  if (visible.isEmpty)
                    _EmptySearch(query: _query.trim(), onClear: _clearSearch),
                  for (var i = 0; i < visible.length; i++)
                    KeyedSubtree(
                      key: ValueKey('settings-group-${visible[i].id}'),
                      child: _GroupView(group: visible[i], index: i),
                    ),
                ],
              ),
            ),
            const SliverSafeArea(
              minimum: EdgeInsets.only(bottom: 140),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search model ───────────────────────────────────────────────────────────

class _Entry {
  const _Entry({
    required this.title,
    required this.child,
    this.keywords = '',
  });

  final String title;
  final String keywords;
  final Widget child;
}

class _Group {
  const _Group({
    required this.id,
    required this.title,
    this.entries = const [],
    this.standalone,
    this.standaloneKeywords = '',
  });

  final String id;
  final String title;
  final List<_Entry> entries;

  /// A self-contained card (such as the security section) that brings its own
  /// rows. It is matched as a whole through [standaloneKeywords].
  final Widget? standalone;
  final String standaloneKeywords;

  int get rowCount => standalone != null ? 1 : entries.length;

  /// Returns this group limited to rows matching every token, or null when
  /// nothing matches. A token matching the group title keeps all rows.
  _Group? filtered(List<String> tokens) {
    if (tokens.isEmpty) return this;
    bool covers(String haystack) {
      final text = haystack.toLowerCase();
      return tokens.every(text.contains);
    }

    final groupTitle = title.toLowerCase();
    if (standalone != null) {
      return covers('$title $standaloneKeywords') ? this : null;
    }
    if (tokens.every(groupTitle.contains)) return this;
    final rows = entries
        .where((e) => covers('$title ${e.title} ${e.keywords}'))
        .toList();
    if (rows.isEmpty) return null;
    return _Group(id: id, title: title, entries: rows);
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group, required this.index});

  final _Group group;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = (40 * index).ms;
    final standalone = group.standalone;
    final Widget card = standalone ??
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < group.entries.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                group.entries[i].child,
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: group.title)
            .animate(delay: delay)
            .fadeIn(duration: 260.ms),
        const SizedBox(height: ArcColors.space8),
        card
            .animate(delay: delay + 40.ms)
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.05),
        const SizedBox(height: ArcColors.space20),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
    required this.resultLabel,
  });

  final TextEditingController controller;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String? resultLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'Search settings',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasText
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClear,
                  )
                : null,
          ),
        ),
        if (resultLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: ArcColors.space8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                resultLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        const SizedBox(height: ArcColors.space4),
      ],
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ArcColors.space32),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: ArcColors.space12),
          Text('No matching settings',
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: ArcColors.space4),
          Text(
            'Nothing found for "$query". Try a word like blur, lock or backup.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ArcColors.space12),
          TextButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ),
    );
  }
}

// ─── Row building blocks ────────────────────────────────────────────────────

/// A title (optional description) above a custom control such as a
/// segmented selector.
class _ChoiceBlock extends StatelessWidget {
  const _ChoiceBlock({
    required this.title,
    required this.child,
    this.description,
    this.liveDescription = false,
  });

  final String title;
  final String? description;
  final bool liveDescription;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ArcColors.space16, vertical: ArcColors.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium)),
          if (description != null) ...[
            const SizedBox(height: ArcColors.space4),
            Semantics(
              liveRegion: liveDescription,
              child: Text(description!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
          const SizedBox(height: ArcColors.space8),
          child,
        ],
      ),
    );
  }
}

/// Sample text rendered at the system text scale so large-text effects are
/// visible before leaving Settings.
class _TextSizePreview extends StatelessWidget {
  const _TextSizePreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final percent = (scale * 100).round();
    final high = ArcContrast.isHigh(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ArcColors.space16, vertical: ArcColors.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true,
              child: Text('Text size preview',
                  style: theme.textTheme.titleMedium)),
          const SizedBox(height: ArcColors.space4),
          Text('System text size: $percent%',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: ArcColors.space8),
          ExcludeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ArcColors.space12),
              decoration: BoxDecoration(
                color: high ? colors.surface : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
                border: Border.all(
                  color: high ? colors.outline : colors.outlineVariant,
                  width: high ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quarterly report.pdf',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('12 pages · 2.4 MB · Opened today',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: ArcColors.space8),
                  Text('The quick brown fox jumps over the lazy dog.',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: ArcColors.space8),
          Text(
            'Change it in your device settings under Display > Font size.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Choice<T> {
  const _Choice({
    required this.value,
    required this.label,
    this.icon,
    this.swatch,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Small filled circle shown before the label (accent colour previews).
  final Color? swatch;

  bool get hasLeading => icon != null || swatch != null;
}

class _SettingsChoices<T> extends StatelessWidget {
  const _SettingsChoices({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.balanceRows = false,
  });

  final List<_Choice<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Avoid stranding a single option on the last row by only using column
  /// counts that divide the number of options.
  final bool balanceRows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final high = ArcContrast.isHigh(context);
    final style =
        theme.textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);
    return LayoutBuilder(builder: (context, constraints) {
      var minimumWidth = 0.0;
      for (final option in options) {
        final painter = TextPainter(
          text: TextSpan(text: option.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width + 24 + (option.hasLeading ? 24 : 0);
        if (width > minimumWidth) minimumWidth = width;
        painter.dispose();
      }
      var columns = ((constraints.maxWidth + 8) / (minimumWidth + 8))
          .floor()
          .clamp(1, options.length);
      if (balanceRows) {
        while (columns > 1 && options.length % columns != 0) {
          columns--;
        }
      } else if (options.any((option) => option.icon != null) &&
          columns < options.length) {
        // Keep theme choices together; do not strand one option on a second row.
        columns = 1;
      }
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      final labelHeight = options.fold<double>(0, (height, option) {
        final painter = TextPainter(
          text: TextSpan(text: option.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: width - 24 - (option.hasLeading ? 24 : 0));
        final measured =
            option.hasLeading && painter.height < 18 ? 18.0 : painter.height;
        painter.dispose();
        return measured > height ? measured : height;
      });
      final height =
          (labelHeight + 24).clamp(ArcColors.minTouchTarget, double.infinity);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((option) {
          final isSelected = option.value == selected;
          final foreground = isSelected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface;
          return SizedBox(
            width: width,
            height: height,
            child: Semantics(
              selected: isSelected,
              inMutuallyExclusiveGroup: true,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(
                      ArcColors.minTouchTarget, ArcColors.minTouchTarget),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  padding: const EdgeInsets.all(12),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: high ? 2 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
                  ),
                  textStyle: style,
                  foregroundColor: foreground,
                  backgroundColor:
                      isSelected ? theme.colorScheme.primary : null,
                ),
                onPressed: () => onSelected(option.value),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (option.swatch != null) ...[
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: option.swatch,
                          shape: BoxShape.circle,
                          border: Border.all(color: foreground, width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else if (option.icon != null) ...[
                      Icon(option.icon, size: 18),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                        child: Text(option.label, textAlign: TextAlign.center)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
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
    final high = ArcContrast.isHigh(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ArcColors.cardRadius),
        side: high
            ? BorderSide(color: theme.colorScheme.outline, width: 2)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
