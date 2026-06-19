import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'security_controller.dart';
import 'pin_pad.dart';
import 'pattern_pad.dart';

class SecuritySettingsDialog extends ConsumerStatefulWidget {
  const SecuritySettingsDialog({super.key});

  @override
  ConsumerState<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends ConsumerState<SecuritySettingsDialog> {
  LockType _selectedType = LockType.pin;
  String? _firstInput;
  String? _errorText;
  bool _isConfirming = false;

  void _handleInput(String input) async {
    if (!_isConfirming) {
      setState(() {
        _firstInput = input;
        _isConfirming = true;
        _errorText = null;
      });
    } else {
      if (_firstInput == input) {
        // Success
        await ref.read(securityControllerProvider.notifier).setLockType(_selectedType);
        await ref.read(securityControllerProvider.notifier).setLockEnabled(true, pinOrPattern: input);
        if (mounted) Navigator.pop(context);
      } else {
        setState(() {
          _errorText = "Inputs don't match. Try again.";
          _isConfirming = false;
          _firstInput = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                HugeIcons.strokeRoundedSecurityLock,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            Text(
              _isConfirming ? 'Confirm ${_selectedType == LockType.pin ? 'PIN' : 'Pattern'}' : 'Set new ${_selectedType == LockType.pin ? 'PIN' : 'Pattern'}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms, delay: 50.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 24),

            if (!_isConfirming)
              SegmentedButton<LockType>(
                segments: const [
                  ButtonSegment(value: LockType.pin, label: Text('PIN'), icon: Icon(HugeIcons.strokeRoundedPasswordValidation)),
                  ButtonSegment(value: LockType.pattern, label: Text('Pattern'), icon: Icon(HugeIcons.strokeRoundedGrid)),
                ],
                selected: {_selectedType},
                onSelectionChanged: (s) {
                  setState(() {
                    _selectedType = s.first;
                    _errorText = null;
                  });
                },
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

            const SizedBox(height: 32),

            if (_selectedType == LockType.pin)
              PinPad(
                onCompleted: _handleInput,
                errorText: _errorText,
                // Using key to force rebuild when confirming vs setting
                key: ValueKey('pin_$_isConfirming'),
              )
            else
              PatternPad(
                onCompleted: _handleInput,
                errorText: _errorText,
                key: ValueKey('pattern_$_isConfirming'),
              ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SecurityVerifyDialog extends ConsumerStatefulWidget {
  const SecurityVerifyDialog({super.key});

  @override
  ConsumerState<SecurityVerifyDialog> createState() => _SecurityVerifyDialogState();
}

class _SecurityVerifyDialogState extends ConsumerState<SecurityVerifyDialog> {
  String? _errorText;

  void _handleInput(String input) async {
    final success = await ref.read(securityControllerProvider.notifier).verifyPinOrPattern(input);
    if (success) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() {
        _errorText = 'Incorrect';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final security = ref.read(securityControllerProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                HugeIcons.strokeRoundedSecurityValidation,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            Text(
              'Verify to Disable',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 24),
            if (security.lockType == LockType.pin)
              PinPad(onCompleted: _handleInput, errorText: _errorText)
            else
              PatternPad(onCompleted: _handleInput, errorText: _errorText),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
