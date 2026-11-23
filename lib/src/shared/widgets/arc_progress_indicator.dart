import 'package:flutter/material.dart';

class ArcProgressIndicator extends StatelessWidget {
  const ArcProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
        child: SizedBox.square(
      dimension: 28,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: theme.colorScheme.primary,
        value: MediaQuery.disableAnimationsOf(context) ? 0.65 : null,
        semanticsLabel: 'Working',
      ),
    ));
  }
}
