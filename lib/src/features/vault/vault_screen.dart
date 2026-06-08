import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'vault_controller.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';
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
  @override
  void initState() {
    super.initState();
    // Verify lock enabled before letting them see this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final security = ref.read(securityControllerProvider);
      if (!security.isLockEnabled) {
         ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable App Lock in Settings first.')),
         );
         Navigator.pop(context);
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
    final vaultState = ref.watch(vaultControllerProvider);

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
