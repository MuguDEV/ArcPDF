import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'security_controller.dart';
import 'shared_lock_overlay.dart';

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
    final security = ref.read(securityControllerProvider);
    // Ignore inactive state because it's triggered by system dialogs, file pickers, etc.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (security.requireLockOnResume) {
        ref.read(securityControllerProvider.notifier).lockApp();
      }
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

class _LockOverlay extends ConsumerWidget {
  const _LockOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SharedLockOverlay(
      title: 'App Locked',
      onVerify: (input) => ref.read(securityControllerProvider.notifier).verifyPinOrPattern(input),
      onBiometricAuth: () => ref.read(securityControllerProvider.notifier).authenticateBiometric(),
    );
  }
}
