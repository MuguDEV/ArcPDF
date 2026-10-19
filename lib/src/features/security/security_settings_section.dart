import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'security_controller.dart';
import 'security_settings_dialog.dart';
import '../../shared/theme/arc_colors.dart';

class SecuritySettingsSection extends ConsumerWidget {
  const SecuritySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final security = ref.watch(securityControllerProvider);
    final ctrl = ref.read(securityControllerProvider.notifier);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ArcColors.cardRadius),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: security.isLockEnabled,
            onChanged: (val) async {
              if (val) {
                // Enable lock
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const SecuritySettingsDialog(),
                );
              } else {
                // Disable lock
                final result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const SecurityVerifyDialog(),
                );
                if (result == true) {
                  ctrl.setLockEnabled(false);
                }
              }
            },
            title: const Text('App Lock'),
            subtitle: const Text('Require PIN or Pattern to open app'),
          ),
          if (security.isLockEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile.adaptive(
              value: security.isBiometricEnabled,
              onChanged: ctrl.setBiometricEnabled,
              title: const Text('Use Biometrics'),
              subtitle: const Text('Unlock with Fingerprint or FaceID'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile.adaptive(
              value: security.requireLockOnResume,
              onChanged: ctrl.setRequireLockOnResume,
              title: const Text('Lock on Resume'),
              subtitle: const Text('Require lock when returning to the app'),
            ),
          ],
        ],
      ),
    );
  }
}
