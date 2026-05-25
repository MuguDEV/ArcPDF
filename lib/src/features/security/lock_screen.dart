import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'security_controller.dart';
import 'pin_pad.dart';
import 'pattern_pad.dart';

class LockScreenWrapper extends ConsumerStatefulWidget {
  const LockScreenWrapper({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockScreenWrapper> createState() => _LockScreenWrapperState();
}

class _LockScreenWrapperState extends ConsumerState<LockScreenWrapper> with WidgetsBindingObserver {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Request biometrics on startup if enabled and locked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBiometrics();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ref.read(securityControllerProvider.notifier).lockApp();
    } else if (state == AppLifecycleState.resumed) {
      _checkBiometrics();
    }
  }

  void _checkBiometrics() async {
    if (_isAuthenticating) return;
    final security = ref.read(securityControllerProvider);
    if (security.isLockEnabled && security.isLocked && security.isBiometricEnabled) {
      _isAuthenticating = true;
      await ref.read(securityControllerProvider.notifier).authenticateBiometric();
      _isAuthenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityControllerProvider);

    return Stack(
      children: [
        widget.child,
        if (security.isLockEnabled && security.isLocked) const _LockOverlay(),
      ],
    );
  }
}

class _LockOverlay extends ConsumerStatefulWidget {
  const _LockOverlay();

  @override
  ConsumerState<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<_LockOverlay> {
  String? _errorText;

  Future<void> _handleInput(String input) async {
    final success = await ref.read(securityControllerProvider.notifier).verifyPinOrPattern(input);
    if (!success) {
      setState(() {
        _errorText = 'Incorrect ${ref.read(securityControllerProvider).lockType == LockType.pin ? 'PIN' : 'Pattern'}';
      });
    } else {
      setState(() {
        _errorText = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final security = ref.watch(securityControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Frosted glass background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Container(
                color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.8 : 0.85),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedSecurityLock,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'App Locked',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your ${security.lockType == LockType.pin ? 'PIN' : 'Pattern'} to continue',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 48),

                    if (security.lockType == LockType.pin)
                      PinPad(
                        onCompleted: _handleInput,
                        errorText: _errorText,
                      )
                    else
                      PatternPad(
                        onCompleted: _handleInput,
                        errorText: _errorText,
                      ),

                    const SizedBox(height: 32),

                    if (security.isBiometricEnabled)
                      TextButton.icon(
                        onPressed: () {
                          ref.read(securityControllerProvider.notifier).authenticateBiometric();
                        },
                        icon: const Icon(HugeIcons.strokeRoundedFingerprintScan),
                        label: const Text('Use Biometrics'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
