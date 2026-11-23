import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/tools/tools_screen.dart';
import 'package:arcpdf/src/features/tools/widgets/tool_card.dart';
import 'package:arcpdf/src/shared/theme/arc_theme.dart';
import 'package:arcpdf/src/theme/arc_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _Box extends Mock implements Box<dynamic> {}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('all tools remain readable at 320px and 3x text in $brightness',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final box = _Box();
      when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
          .thenAnswer((call) => call.namedArguments[#defaultValue]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsControllerProvider
              .overrideWith((ref) => SettingsController(box)),
        ],
        child: MaterialApp(
          theme: buildArcTheme(
            brightness: brightness,
            textTheme: ArcTypography.textTheme(brightness,
                family: AppFontFamily.system),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(3),
                disableAnimations: true),
            child: child!,
          ),
          home: const ToolsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      for (final title in [
        'Merge PDFs',
        'Split PDF',
        'Organize pages',
        'Compress PDF',
        'Edit metadata',
        'Images to PDF',
        'PDF to Images'
      ]) {
        await tester.scrollUntilVisible(find.text(title), 200);
        await tester.pumpAndSettle();
        final card = find.ancestor(
            of: find.text(title), matching: find.byType(ToolCard));
        expect(tester.getSize(card).height, greaterThan(80));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('tool cards activate once by touch and keyboard', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ToolCard(
      title: 'Merge PDFs',
      subtitle: 'Combine documents',
      icon: ArcIcons.merge,
      onTap: () => taps++,
    ))));
    await tester.tap(find.text('Merge PDFs'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 2);
  });
}
