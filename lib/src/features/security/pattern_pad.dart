import 'package:flutter/material.dart';
import 'package:pattern_lock/pattern_lock.dart';


import '../settings/haptic_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PatternPad extends ConsumerWidget {
  const PatternPad({
    super.key,
    required this.onCompleted,
    this.errorText,
  });

  final ValueChanged<String> onCompleted;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorText != null) ...[
          Text(errorText!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: 300,
          height: 300,
          child: PatternLock(
            selectedColor: theme.colorScheme.primary,
            pointRadius: 8,
            showInput: true,
            dimension: 3,
            relativePadding: 0.7,
            selectThreshold: 25,
            fillPoints: true,
            onInputComplete: (List<int> input) async {
              ref.read(hapticServiceProvider).vibrate();
              onCompleted(input.join());
            },
          ),
        ),
      ],
    );
  }
}
