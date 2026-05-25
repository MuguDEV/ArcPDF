import 'package:flutter/material.dart';
import 'package:pattern_lock/pattern_lock.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';

class PatternPad extends StatelessWidget {
  const PatternPad({
    super.key,
    required this.onCompleted,
    this.errorText,
  });

  final ValueChanged<String> onCompleted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
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
              HapticFeedback.selectionClick();
              if (await Vibration.hasVibrator() == true) {
                Vibration.vibrate(duration: 10, amplitude: 50);
              }
              onCompleted(input.join());
            },
          ),
        ),
      ],
    );
  }
}
