import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/tools/tool_action_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _Box extends Mock implements Box<dynamic> {}

void main() {
  late ProviderContainer container;
  late SettingsController settings;
  late List<MethodCall> feedback;
  final status = ValueNotifier(false);

  setUp(() {
    status.value = false;
    feedback = [];
    final box = _Box();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    settings = SettingsController(box);
    container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith((ref) => settings),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') feedback.add(call);
      return null;
    });
  });

  tearDown(() {
    container.dispose();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  tearDownAll(status.dispose);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            key: const ValueKey('tool-status'),
            valueListenable: status,
            builder: (_, success, __) => ToolActionDialog(
              title: 'Save PDF',
              message: success ? 'Saved' : 'Saving',
              isLoading: !success,
              outputPath: success ? '/output.pdf' : null,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  for (final enabled in [false, true]) {
    testWidgets('initial success respects haptic preference $enabled',
        (tester) async {
      await settings.setUseHaptics(enabled);
      status.value = true;
      await mount(tester);
      expect(feedback, hasLength(enabled ? 1 : 0));
      if (enabled) {
        expect(feedback.single.arguments, 'HapticFeedbackType.lightImpact');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading completion buzzes once and reads the current preference',
      (tester) async {
    await settings.setUseHaptics(false);
    await mount(tester);
    expect(feedback, isEmpty);
    await settings.setUseHaptics(true);
    status.value = true;
    await tester.pumpAndSettle();
    expect(feedback, hasLength(1));
    tester.element(find.byKey(const ValueKey('tool-status'))).markNeedsBuild();
    await tester.pumpAndSettle();
    // The same dialog stays successful without replaying its completion cue.
    expect(feedback, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
