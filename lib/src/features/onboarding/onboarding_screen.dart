import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/logger.dart';
import '../../shared/theme/arc_colors.dart';
import '../pdf/application/pdf_library_controller.dart';
import '../settings/settings_controller.dart';
import 'gesture_illustration.dart';
import 'onboarding_controller.dart';

const _stepCount = 3;
const _stepTitles = [
  'Let ArcPDF find your PDFs',
  'Keep files in a private vault',
  'Read with your hands',
];

/// First-run onboarding: permissions, vault, reader gestures.
///
/// Shown by `AppShell` after the splash while [onboardingCompletedProvider] is
/// false. Finishing (or skipping) calls `complete()`, which hides it for good.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  int _furthest = 0;
  bool _leaving = false;
  bool _requesting = false;
  StoragePermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    AppLogger.event('onboarding.shown');
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      ref.read(settingsControllerProvider).lowPowerMode;

  bool get _isLast => _index == _stepCount - 1;

  void _goTo(int page) {
    final target = page.clamp(0, _stepCount - 1);
    if (target == _index || !_pages.hasClients) return;
    if (_reduceMotion) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      _index = page;
      _furthest = math.max(_furthest, page);
    });
    AppLogger.event('onboarding.step', fields: {'step': page + 1});
  }

  void _next() => _isLast ? _finish(skipped: false) : _goTo(_index + 1);

  void _finish({required bool skipped}) {
    if (_leaving) return;
    if (skipped) {
      AppLogger.event('onboarding.skipped', fields: {'step': _index + 1});
    } else {
      AppLogger.event('onboarding.completed',
          fields: {'furthestStep': _furthest + 1});
    }
    if (_reduceMotion) {
      ref.read(onboardingCompletedProvider.notifier).complete();
    } else {
      setState(() => _leaving = true);
    }
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    if (_permission == StoragePermissionStatus.permanentlyDenied) {
      AppLogger.event('onboarding.permission.open_settings');
      await openAppSettings();
      return;
    }
    setState(() => _requesting = true);
    AppLogger.event('onboarding.permission.requested');
    // Reuse the library's own permission flow; never duplicate it here.
    try {
      await ref
          .read(pdfLibraryControllerProvider.notifier)
          .refresh(requestPermission: true);
    } catch (_) {
      // The controller reports its own failures; fall through to its state.
    }
    if (!mounted) return;
    final status = ref.read(pdfLibraryControllerProvider).permissionStatus;
    setState(() {
      _requesting = false;
      _permission = status;
    });
    AppLogger.event('onboarding.permission.result',
        fields: {'status': status.name});
  }

  void _notNow() {
    AppLogger.event('onboarding.permission.not_now');
    _goTo(1);
  }

  void _arrow(bool forward) {
    // Arrow keys follow reading direction.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _goTo(_index + (forward != rtl ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context) &&
        !ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));
    final fade = animate ? const Duration(milliseconds: 240) : Duration.zero;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_index - 1);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _arrow(true),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _arrow(false),
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Scaffold(
            body: SafeArea(
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: fade,
                curve: Curves.easeOut,
                onEnd: () {
                  if (_leaving) {
                    ref.read(onboardingCompletedProvider.notifier).complete();
                  }
                },
                child: IgnorePointer(
                  ignoring: _leaving,
                  child: Column(
                    children: [
                      _TopBar(
                        showBack: _index > 0,
                        showSkip: !_isLast,
                        onBack: () => _goTo(_index - 1),
                        onSkip: () => _finish(skipped: true),
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pages,
                          onPageChanged: _onPageChanged,
                          children: [
                            _PageFlow(
                              controller: _pages,
                              index: 0,
                              animate: animate,
                              child: _PermissionCard(
                                status: _permission,
                                requesting: _requesting,
                                onAllow: _requestPermission,
                                onNotNow: _notNow,
                              ),
                            ),
                            _PageFlow(
                              controller: _pages,
                              index: 1,
                              animate: animate,
                              child: const _VaultCard(),
                            ),
                            _PageFlow(
                              controller: _pages,
                              index: 2,
                              animate: animate,
                              child: _GesturesCard(
                                animate: animate,
                                active: _index == 2 && !_leaving,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _BottomBar(
                        index: _index,
                        animate: animate,
                        isLast: _isLast,
                        onDot: _goTo,
                        onNext: _next,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
  });

  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ArcColors.minTouchTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ArcColors.space8),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                onPressed: onBack,
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  minimumSize: const Size(
                      ArcColors.minTouchTarget, ArcColors.minTouchTarget),
                ),
              ),
            const Spacer(),
            if (showSkip)
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                      ArcColors.minTouchTarget, ArcColors.minTouchTarget),
                ),
                child: const Text('Skip'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.animate,
    required this.isLast,
    required this.onDot,
    required this.onNext,
  });

  final int index;
  final bool animate;
  final bool isLast;
  final ValueChanged<int> onDot;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration =
        animate ? const Duration(milliseconds: 280) : Duration.zero;
    return Padding(
      padding: const EdgeInsets.fromLTRB(ArcColors.screenPadding, 0,
          ArcColors.screenPadding, ArcColors.space16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // One live region announces "Step N of 3" on every page change.
              Semantics(
                container: true,
                liveRegion: true,
                label: 'Step ${index + 1} of $_stepCount',
                excludeSemantics: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _stepCount; i++)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onDot(i),
                        child: SizedBox(
                          width: ArcColors.minTouchTarget,
                          height: ArcColors.minTouchTarget,
                          child: Center(
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              width: i == index ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == index
                                    ? scheme.onSurface
                                    : scheme.outlineVariant,
                                borderRadius:
                                    BorderRadius.circular(ArcColors.pillRadius),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: ArcColors.space4),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Text(
                    isLast ? 'Get started' : 'Next',
                    key: ValueKey(isLast),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gentle parallax and cross-fade driven by the page position.
class _PageFlow extends StatelessWidget {
  const _PageFlow({
    required this.controller,
    required this.index,
    required this.animate,
    required this.child,
  });

  final PageController controller;
  final int index;
  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var delta = 0.0;
        if (controller.hasClients && controller.position.haveDimensions) {
          delta =
              ((controller.page ?? index.toDouble()) - index).clamp(-1.0, 1.0);
        }
        if (delta == 0) return child!;
        return Opacity(
          opacity: 1 - 0.75 * Curves.easeIn.transform(delta.abs()),
          child: Transform.translate(
            offset: Offset(delta * 36, 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// Scrollable, centered card body: safe at 320px wide and 3x text.
class _CardScaffold extends StatelessWidget {
  const _CardScaffold({
    required this.hero,
    required this.title,
    required this.children,
  });

  final Widget hero;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: ArcColors.screenPadding + 4,
            vertical: ArcColors.space8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight:
                  math.max(0, constraints.maxHeight - 2 * ArcColors.space8)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: hero),
                  const SizedBox(height: ArcColors.space24),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: ArcColors.space12),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: 44, color: scheme.onSurface),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.title});

  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ArcColors.space8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: scheme.onSurface),
            const SizedBox(width: ArcColors.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.status,
    required this.requesting,
    required this.onAllow,
    required this.onNotNow,
  });

  final StoragePermissionStatus? status;
  final bool requesting;
  final VoidCallback onAllow;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = status == StoragePermissionStatus.granted;
    final blocked = status == StoragePermissionStatus.permanentlyDenied;
    final label = granted
        ? 'Access allowed'
        : blocked
            ? 'Open app settings'
            : status == StoragePermissionStatus.denied
                ? 'Try again'
                : 'Allow access';
    final message = switch (status) {
      StoragePermissionStatus.granted =>
        'Access allowed. Your PDFs will appear on Home.',
      StoragePermissionStatus.denied =>
        'Access was not granted. You can try again, or allow it later from Home.',
      StoragePermissionStatus.permanentlyDenied =>
        'Access is blocked. Enable file access for ArcPDF in system settings.',
      null => null,
    };
    return _CardScaffold(
      hero: const _IconHero(Icons.folder_open_rounded),
      title: _stepTitles[0],
      children: [
        const _Body(
          'ArcPDF lists the PDFs already on your device. On Android 11 and '
          'newer this needs All files access, a special permission you '
          'switch on in system settings.',
        ),
        const SizedBox(height: ArcColors.space16),
        const _InfoRow(
          icon: Icons.picture_as_pdf_rounded,
          text: 'Only used to find PDF documents.',
        ),
        const _InfoRow(
          icon: Icons.tune_rounded,
          text: 'You can change it any time in system settings.',
        ),
        const SizedBox(height: ArcColors.space16),
        FilledButton.tonalIcon(
          onPressed: requesting || granted ? null : onAllow,
          icon: requesting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(granted
                  ? Icons.check_rounded
                  : blocked
                      ? Icons.settings_rounded
                      : Icons.folder_open_rounded),
          label: Text(label, textAlign: TextAlign.center),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
        if (!granted)
          TextButton(
            onPressed: requesting ? null : onNotNow,
            style: TextButton.styleFrom(
              minimumSize:
                  const Size(double.infinity, ArcColors.minTouchTarget),
            ),
            child: const Text('Not now'),
          ),
        if (message != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: ArcColors.space8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
            ),
          ),
      ],
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _CardScaffold(
      hero: const _IconHero(Icons.lock_outline_rounded),
      title: _stepTitles[1],
      children: [
        const _Body(
          'The vault is a private space inside ArcPDF for documents you '
          'would rather keep out of your everyday library.',
        ),
        const SizedBox(height: ArcColors.space16),
        const _InfoRow(
          icon: Icons.shield_outlined,
          title: 'Optional App Lock',
          text: 'Turn it on to require authentication before the vault opens.',
        ),
        const _InfoRow(
          icon: Icons.visibility_off_outlined,
          title: 'Kept apart',
          text: 'Vault files stay out of your regular lists.',
        ),
        const SizedBox(height: ArcColors.space16),
        MergeSemantics(
          child: Container(
            padding: const EdgeInsets.all(ArcColors.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ArcColors.cardRadius),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.settings_outlined, color: scheme.onSurface),
                const SizedBox(width: ArcColors.space16),
                Expanded(
                  child: Text(
                    'Set up later in Settings. The vault needs App Lock, '
                    'and nothing is required today.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GesturesCard extends StatelessWidget {
  const _GesturesCard({required this.animate, required this.active});

  final bool animate;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _CardScaffold(
      hero: GestureIllustration(animate: animate, active: active),
      title: _stepTitles[2],
      children: const [
        _InfoRow(
          icon: Icons.swipe_rounded,
          title: 'Fling to travel',
          text: 'A fast fling carries you across many pages at once.',
        ),
        _InfoRow(
          icon: Icons.touch_app_rounded,
          title: 'Tap',
          text: 'Tap the page to show or hide the toolbar.',
        ),
        _InfoRow(
          icon: Icons.zoom_in_rounded,
          title: 'Pinch or double-tap',
          text: 'Zoom in and back out.',
        ),
        _InfoRow(
          icon: Icons.pan_tool_alt_rounded,
          title: 'Long-press a card',
          text: 'Open actions for any PDF in your library.',
        ),
      ],
    );
  }
}
