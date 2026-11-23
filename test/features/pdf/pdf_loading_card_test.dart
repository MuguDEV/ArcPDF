import 'package:arcpdf/src/features/pdf/home/widgets/pdf_card_shimmer.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shimmer/shimmer.dart';

class _Box extends Mock implements Box<dynamic> {}

void main() {
  for (final lowPower in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets('loading card settles: battery=$lowPower, reduced=$reduced',
          (tester) async {
        final box = _Box();
        when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
            .thenAnswer((call) =>
                call.positionalArguments.first == 'lowPowerMode'
                    ? lowPower
                    : call.namedArguments[#defaultValue]);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              settingsControllerProvider
                  .overrideWith((ref) => SettingsController(box)),
            ],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: reduced),
                    child: child!),
                home: const Scaffold(
                    body: SizedBox(width: 320, child: PdfCardShimmer())))));
        expect(find.byType(Shimmer),
            lowPower || reduced ? findsNothing : findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
