import 'dart:developer';

import 'package:arcpdf/src/shared/utils/traced_page_transitions_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Route builds preserve the enclosing synchronous timeline span',
      (tester) async {
    const builder = TracedZoomPageTransitionsBuilder();
    final route = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        for (final progress in [0.0, 0.5, 1.0, 1.0]) {
          Timeline.startSync('test enclosing build');
          try {
            builder.buildTransitions(
              route,
              context,
              AlwaysStoppedAnimation<double>(progress),
              const AlwaysStoppedAnimation<double>(0),
              const SizedBox.shrink(),
            );
          } finally {
            Timeline.finishSync();
          }
        }
        return const SizedBox.shrink();
      }),
    ));

    expect(tester.takeException(), isNull);
  });
}
