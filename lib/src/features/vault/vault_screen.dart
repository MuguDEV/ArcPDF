import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'vault_controller.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../pdf/domain/pdf_file_item.dart';
import '../security/security_controller.dart';
import '../security/shared_lock_overlay.dart';
import '../../shared/widgets/arc_progress_indicator.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  bool _noLock = false;

  @override
  void initState() {
    super.initState();
    // Verify lock enabled before letting them see this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final security = ref.read(securityControllerProvider);
      if (!security.isLockEnabled) {
         setState(() {
           _noLock = true;
         });
      } else {
         _authenticate();
      }
    });
  }

  Future<void> _authenticate() async {
    final security = ref.read(securityControllerProvider);
    bool success = false;

    if (security.isBiometricEnabled) {
       success = await ref.read(securityControllerProvider.notifier).authenticateBiometric();
    }

    if (!success) {
      // Need manual PIN/Pattern entry
      success = await _showManualAuth(security.lockType);
    }

    if (success) {
      ref.read(vaultControllerProvider.notifier).setUnlocked(true);
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<bool> _showManualAuth(LockType lockType) async {
    return await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, _, __) {
          return SharedLockOverlay(
            title: 'Unlock Vault',
            onVerify: (val) async {
              final valid = await ref.read(securityControllerProvider.notifier).verifyPinOrPattern(val);
              if (valid && context.mounted) {
                Navigator.pop(context, true);
              }
              return valid;
            },
            onBiometricAuth: () async {
              final success = await ref.read(securityControllerProvider.notifier).authenticateBiometric();
              if (success && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          );
        },
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vaultState = ref.watch(vaultControllerProvider);

    if (_noLock) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure Vault')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  HugeIcons.strokeRoundedLockPassword,
                  size: 80,
                  color: theme.colorScheme.error,
                ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                Text(
                  'App Lock Required',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.2),
                const SizedBox(height: 12),
                Text(
                  'To use the Secure Vault, you need to enable App Lock in Settings first. This ensures your files are protected.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.2),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // Provide a nice feedback interaction and close the page
                    HapticFeedback.selectionClick();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.2),
              ],
            ),
          ),
        ),
      );
    }

    if (!vaultState.isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure Vault')),
        body: const Center(child: ArcProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Vault'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(vaultControllerProvider.notifier).setUnlocked(false);
            Navigator.pop(context);
          },
        ),
      ),
      body: vaultState.isLoading
          ? const Center(child: ArcProgressIndicator())
          : vaultState.vaultFiles.isEmpty
              ? const Center(child: Text('Vault is empty'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vaultState.vaultFiles.length,
                  itemBuilder: (context, index) {
                    final item = vaultState.vaultFiles[index];
                    return ListTile(
                      leading: const Icon(HugeIcons.strokeRoundedLockPassword),
                      title: Text(item.name),
                      subtitle: const Text('Encrypted Vault File'),
                      onTap: () async {
                         final tempFile = await ref.read(vaultControllerProvider.notifier).decryptToTempFile(item);
                         try {
                           if (tempFile != null && context.mounted) {
                             final tempItem = PdfFileItem.fromFile(tempFile);
                             if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(item: tempItem)));
                           }
                         } finally {
                            if (tempFile != null && tempFile.existsSync()) {
                              tempFile.deleteSync();
                            }
                         }
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.restore),
                        onPressed: () async {
                           HapticFeedback.mediumImpact();
                           final downloads = await getDownloadsDirectory(); // path_provider
                           // Fallback to Download dir
                           if (downloads != null) {
                             final success = await ref.read(vaultControllerProvider.notifier).restoreFromVault(item, downloads.path);
                             if (success && context.mounted) {
                                HapticFeedback.selectionClick();
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored to Downloads folder')));
                             } else if (!success && context.mounted) {
                                HapticFeedback.heavyImpact();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to restore file')));
                             }
                           }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
