import 'package:arcpdf/src/shared/theme/arc_control_theme.dart';
import 'package:arcpdf/src/shared/widgets/dynamic_island_notification.dart';
import 'package:arcpdf/src/shared/widgets/sheet/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: brightness,
    ).copyWith(
      primary: brightness == Brightness.light ? Colors.black : Colors.white,
      onPrimary: brightness == Brightness.light ? Colors.white : Colors.black,
    );
    final theme = applyArcControlTheme(ThemeData(colorScheme: colors));
    test('$brightness controls use contrasting theme pairs', () {
      const selected = {WidgetState.selected};
      expect(theme.radioTheme.fillColor!.resolve(selected), colors.primary);
      expect(theme.checkboxTheme.fillColor!.resolve(selected), colors.primary);
      expect(
          theme.checkboxTheme.checkColor!.resolve(selected), colors.onPrimary);
      expect(theme.switchTheme.trackColor!.resolve(selected), colors.primary);
      expect(theme.switchTheme.thumbColor!.resolve(selected), colors.onPrimary);
      expect(theme.textSelectionTheme.cursorColor, colors.primary);
      expect(theme.sliderTheme.thumbColor, colors.primary);
      expect(theme.snackBarTheme.backgroundColor, colors.surfaceContainerHigh);
      expect(theme.snackBarTheme.contentTextStyle!.color, colors.onSurface);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('$brightness notices share snackbar styling and dismiss action',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => DynamicIslandNotification.show(
              context,
              'Document moved',
              icon: Icons.check,
            ),
            child: const Text('Notify'),
          );
        })),
      ));
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.showCloseIcon, isTrue);
      final context = tester.element(find.text('Document moved'));
      expect(DefaultTextStyle.of(context).style.color, colors.onSurface);
      expect(find.text('Document moved'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Document moved'), findsNothing);
    });

    testWidgets('$brightness sheet radio wraps enlarged labels',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: AppBottomSheet(
              child: SheetRadioRow<int>(
                value: 1,
                groupValue: 1,
                label: 'A long document display option',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      final icon = tester.widget<Icon>(find.byIcon(Icons.radio_button_checked));
      expect(icon.color, colors.primary);
      expect(tester.getSize(find.byType(SheetRadioRow<int>)).height,
          greaterThan(56));
    });
  }
}
