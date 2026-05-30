import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'security_controller.dart';
import 'pin_pad.dart';
import 'pattern_pad.dart';

class SharedLockOverlay extends ConsumerStatefulWidget {
  final Future<bool> Function(String) onVerify;
  final VoidCallback onBiometricAuth;
  final String title;

  const SharedLockOverlay({
    super.key,
    required this.onVerify,
    required this.onBiometricAuth,
    required this.title,
  });

  @override
  ConsumerState<SharedLockOverlay> createState() => _SharedLockOverlayState();
}

class _SharedLockOverlayState extends ConsumerState<SharedLockOverlay> {
  String? _errorText;

  Future<void> _handleInput(String input) async {
    final success = await widget.onVerify(input);
    if (!success) {
      if (mounted) {
        setState(() {
          _errorText = 'Incorrect ${ref.read(securityControllerProvider).lockType == LockType.pin ? 'PIN' : 'Pattern'}';
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _errorText = null;
        });
      }
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
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                    const SizedBox(height: 24),
                    Text(
                      widget.title,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ).animate().fadeIn(duration: 400.ms, delay: 50.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your ${security.lockType == LockType.pin ? 'PIN' : 'Pattern'} to continue',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
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
                        onPressed: widget.onBiometricAuth,
                        icon: const Icon(HugeIcons.strokeRoundedFingerprintScan),
                        label: const Text('Use Biometrics'),
                      ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
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
