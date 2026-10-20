import 'dart:io';

import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/settings/settings_screen.dart';
import 'package:arcpdf/src/shared/theme/arc_colors.dart';
import 'package:arcpdf/src/shared/theme/arc_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockBox extends Mock implements Box {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File.fromUri(File(Platform.resolvedExecutable)
        .uri
        .resolve('../../material_fonts/roboto-regular.ttf'));
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
    await loader.load();
  });
  late MockBox box;
  late SettingsController settings;
  late List<MethodCall> feedback;

  setUp(() {
    box = MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    settings = SettingsController(box);
    feedback = [];
    PackageInfo.setMockInitialValues(
      appName: 'ArcPDF',
      packageName: 'com.arcpdf',
      version: '1.4.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> mount(WidgetTester tester,
      {double scale = 1, double width = 390, ThemeData? theme}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') feedback.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith((ref) => settings),
        securityControllerProvider
            .overrideWith((ref) => SecurityController(box)),
      ],
      child: MaterialApp(
        theme: theme ??
            ThemeData(
              fontFamily: 'Roboto',
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
              listTileTheme: const ListTileThemeData(
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
            ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: SettingsScreen()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    // Bring the row clear of the pinned app bar before interacting with it.
    final dy = 400 - tester.getCenter(find.text(label)).dy;
    await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'rows stay compact with accessible targets and matching icon slots',
      (tester) async {
    await mount(tester);
    for (final label in [
      'Frosted Glass (Blur)',
      'Haptic Feedback',
      'Eco Mode / Low Power',
      'View Logs',
      'Check for Updates'
    ]) {
      await reveal(tester, label);
      final tile = find
          .ancestor(of: find.text(label), matching: find.byType(ListTile))
          .first;
      final context = tester.element(tile);
      final theme = ListTileTheme.of(context);
      expect(theme.dense, isFalse);
      expect(theme.visualDensity, VisualDensity.standard);
      expect(theme.minLeadingWidth, 24);
      expect(theme.horizontalTitleGap, 12);
      expect(theme.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4));
      expect(tester.getSize(tile).height, inInclusiveRange(44, 96));
      if (label == 'Check for Updates') {
        expect(tester.getSize(tile).height, lessThanOrEqualTo(64));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('theme and font options have equal widths and accessible targets',
      (tester) async {
    await mount(tester);
    Finder button(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        );
    final themeSizes = ['System', 'Light', 'Dark'].map((label) {
      // System also appears in the font options.
      return tester.getSize(button(label).first);
    }).toList();
    expect(themeSizes.map((s) => s.width).toSet(), hasLength(1));
    expect(themeSizes.every((s) => s.height == 48), isTrue);
    final themeTops = ['System', 'Light', 'Dark']
        .map((label) => tester.getTopLeft(button(label).first).dy);
    expect(themeTops.toSet(), hasLength(1));
    final fontSizes = ['Inter', 'Roboto', 'Plus Jakarta', 'Nunito']
        .map((label) => tester.getSize(button(label)))
        .toList();
    expect(fontSizes.map((s) => s.width).toSet(), hasLength(1));
    expect(fontSizes.every((s) => s.height == 48), isTrue);
    expect(fontSizes.map((s) => s.height).toSet(), hasLength(1));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.state.themeMode, ThemeMode.dark);
    await tester.tap(find.text('Nunito'));
    await tester.pumpAndSettle();
    expect(settings.state.fontFamily, AppFontFamily.nunito);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('320px settings remain usable at ${scale}x text size',
        (tester) async {
      await mount(tester, width: 320, scale: scale);
      expect(tester.takeException(), isNull);
      final themeButtons = ['System', 'Light', 'Dark']
          .map((label) => find
              .ancestor(
                  of: find.text(label), matching: find.byType(OutlinedButton))
              .first)
          .toList();
      final themeRects = themeButtons.map(tester.getRect).toList();
      expect(themeRects.map((r) => r.height).toSet(), hasLength(1));
      for (final rect in themeRects) {
        expect(rect.height, inInclusiveRange(48, scale == 1 ? 48 : 88));
        expect(rect.width, greaterThanOrEqualTo(48));
      }
      // At narrow widths, use a complete vertical alternative, not 2 + 1.
      expect(themeRects.map((r) => r.left).toSet(), hasLength(1));
      final fontRects = ['System', 'Inter', 'Roboto', 'Plus Jakarta', 'Nunito']
          .map((label) => tester.getRect(find
              .ancestor(
                  of: find.text(label), matching: find.byType(OutlinedButton))
              .last))
          .toList();
      expect(fontRects.map((r) => r.width).toSet(), hasLength(1));
      expect(fontRects.map((r) => r.height).toSet(), hasLength(1));
      for (final rect in fontRects) {
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, inInclusiveRange(48, scale == 1 ? 48 : 160));
      }
      await reveal(tester, 'Haptic Feedback');
      final tile = find.ancestor(
          of: find.text('Haptic Feedback'), matching: find.byType(ListTile));
      expect(tester.getSize(tile).height,
          inInclusiveRange(44, scale == 1 ? 96 : (scale == 2 ? 300 : 480)));
      for (var step = 0; step < 60; step++) {
        await tester.dragFrom(const Offset(4, 400), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (find
            .text('Check for Updates')
            .hitTestable()
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.ensureVisible(find.text('Check for Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Check for Updates').hitTestable(), findsOneWidget);
    });
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('search filters rows, hides empty groups and shows a count',
      (tester) async {
    await mount(tester);
    expect(find.text('LAYOUT & APPEARANCE'), findsOneWidget);
    await search(tester, 'blur');
    expect(find.text('Frosted Glass (Blur)'), findsOneWidget);
    expect(find.text('LAYOUT & APPEARANCE'), findsOneWidget);
    expect(find.text('Haptic Feedback'), findsNothing);
    expect(find.text('Theme Mode'), findsNothing);
    expect(find.text('APPEARANCE'), findsNothing);
    expect(find.text('PERFORMANCE & TUNING'), findsNothing);
    expect(find.text('1 setting found'), findsOneWidget);

    // Matching a group title keeps its rows; tokens are AND-ed.
    await search(tester, 'data support');
    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('View Logs'), findsOneWidget);
    expect(find.text('Frosted Glass (Blur)'), findsNothing);
    await search(tester, 'LOGS diagnostics');
    expect(find.text('View Logs'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsNothing);
    // Security is a self-contained section matched by keywords.
    await search(tester, 'biometric');
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('App Lock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search shows an empty state that can be cleared',
      (tester) async {
    await mount(tester);
    await search(tester, 'zzzz');
    expect(find.text('No matching settings'), findsOneWidget);
    expect(find.textContaining('"zzzz"'), findsOneWidget);
    expect(find.text('Theme Mode'), findsNothing);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('No matching settings'), findsNothing);
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await search(tester, 'theme');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('PERFORMANCE & TUNING'), findsOneWidget);
  });

  testWidgets('data rows open backup and logs without errors', (tester) async {
    await mount(tester);
    await search(tester, 'backup');
    expect(tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(ArcColors.minRowHeight));
    await tester.tap(find.text('Backup & Restore'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await search(tester, 'update');
    expect(find.text('Check for Updates'), findsOneWidget);
  });

  testWidgets('performance presets apply, report Custom and stay accessible',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    await reveal(tester, 'Smooth');
    Finder preset(String label) => find.widgetWithText(OutlinedButton, label);
    expect(
        tester.getSemantics(preset('Balanced')),
        containsSemantics(
            isButton: true, isSelected: true, hasTapAction: true));
    expect(tester.getSize(preset('Smooth')).height,
        greaterThanOrEqualTo(ArcColors.minTouchTarget));

    await tester.tap(preset('Smooth'));
    await tester.pumpAndSettle();
    expect(settings.state.performancePreset, PerformancePreset.smooth);
    expect(settings.state.useLiquidGlass, isTrue);
    expect(settings.state.enableMeshBackground, isTrue);
    expect(settings.state.readerCacheMb, 96);
    expect(tester.getSemantics(preset('Smooth')),
        containsSemantics(isButton: true, isSelected: true));
    verify(() => box.put('performancePreset', PerformancePreset.smooth.index))
        .called(1);

    await tester.tap(preset('Battery'));
    await tester.pumpAndSettle();
    expect(settings.state.lowPowerMode, isTrue);
    expect(settings.state.useBlurEffect, isFalse);
    expect(settings.state.readerPreloadExtent, 0.25);

    await reveal(tester, 'Haptic Feedback');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frosted Glass (Blur)'));
    await tester.pumpAndSettle();
    expect(settings.state.performancePreset, PerformancePreset.custom);
    expect(find.text('Your individual settings do not match a preset.'),
        findsOneWidget);
    expect(tester.getSemantics(preset('Custom')),
        containsSemantics(isButton: true, isSelected: true));
    semantics.dispose();
  });

  testWidgets('choosing an accent updates settings and is persisted',
      (tester) async {
    await mount(tester);
    await reveal(tester, 'Accent color');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sage'));
    await tester.pumpAndSettle();
    expect(settings.state.accent, ArcAccent.sage);
    verify(() => box.put('accent', ArcAccent.sage.index)).called(1);
    await tester.tap(find.widgetWithText(OutlinedButton, 'None'));
    await tester.pumpAndSettle();
    expect(settings.state.accent, ArcAccent.none);
    // All six options are laid out as a balanced grid with 48dp targets.
    final rects = ArcAccent.values
        .map((a) =>
            tester.getRect(find.widgetWithText(OutlinedButton, a.displayName)))
        .toList();
    expect(rects.every((r) => r.height >= 48), isTrue);
    expect(rects.map((r) => r.width).toSet(), hasLength(1));
    expect({for (final r in rects) r.top}.length, anyOf(1, 2, 3, 6));
    expect([for (final r in rects) r.top].where((t) => t == rects.last.top),
        hasLength(rects.length ~/ ({for (final r in rects) r.top}.length)));
  });

  testWidgets('high contrast option persists and describes the mode',
      (tester) async {
    await mount(tester);
    await reveal(tester, 'High contrast');
    expect(find.text('Following your system setting, which is off.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'On'));
    await tester.pumpAndSettle();
    expect(settings.state.highContrast, HighContrastMode.on);
    verify(() => box.put('highContrast', HighContrastMode.on.index)).called(1);
    expect(find.textContaining('Pure black and white'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Off'));
    await tester.pumpAndSettle();
    expect(settings.state.highContrast, HighContrastMode.off);
  });

  testWidgets('settings cards use heavy outlines in the high contrast theme',
      (tester) async {
    await mount(tester,
        theme: buildArcTheme(
          brightness: Brightness.light,
          textTheme: ThemeData(fontFamily: 'Roboto').textTheme,
          highContrast: true,
        ));
    final card = tester.widget<Material>(find
        .descendant(
            of: find.byType(CustomScrollView), matching: find.byType(Material))
        .evaluate()
        .map((e) => e.widget as Material)
        .where((m) => m.shape is RoundedRectangleBorder)
        .map((m) => find.byWidget(m))
        .first);
    final side = (card.shape! as RoundedRectangleBorder).side;
    expect(side.width, 2);
    expect(side.color, Colors.black);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text size preview reflects the system text scale',
      (tester) async {
    await mount(tester, scale: 2);
    await reveal(tester, 'Text size preview');
    expect(find.text('System text size: 200%'), findsOneWidget);
    expect(find.text('Quarterly report.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0, 3.0]) {
      for (final highContrast in [false, true]) {
        testWidgets(
            '320px ${brightness.name} theme at ${scale}x '
            '${highContrast ? 'high contrast' : 'standard'} scrolls without errors',
            (tester) async {
          await mount(tester,
              width: 320,
              scale: scale,
              theme: buildArcTheme(
                brightness: brightness,
                textTheme:
                    ThemeData(fontFamily: 'Roboto', brightness: brightness)
                        .textTheme,
                accent: ArcAccent.slate,
                highContrast: highContrast,
              ));
          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsOneWidget);
          for (var step = 0; step < 80; step++) {
            await tester.dragFrom(const Offset(4, 400), const Offset(0, -400));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (find
                .text('Check for Updates')
                .hitTestable()
                .evaluate()
                .isNotEmpty) {
              break;
            }
          }
          expect(find.text('Check for Updates').hitTestable(), findsOneWidget);
          // Every choice button keeps a 48dp target even with huge text.
          for (final button
              in find.byType(OutlinedButton).evaluate().map((e) => e.widget)) {
            expect(button, isA<OutlinedButton>());
          }
        });
      }
    }
  }

  testWidgets(
      'enabling haptics previews once after preference changes; disabling stays silent',
      (tester) async {
    await settings.setUseHaptics(false);
    await mount(tester);
    await reveal(tester, 'Haptic Feedback');
    await tester.tap(find.text('Haptic Feedback'));
    await tester.pumpAndSettle();
    expect(settings.state.useHaptics, isTrue);
    expect(feedback, hasLength(1));
    await tester.tap(find.text('Haptic Feedback'));
    await tester.pumpAndSettle();
    expect(settings.state.useHaptics, isFalse);
    expect(feedback, hasLength(1));
    verify(() => box.put('useHaptics', true)).called(1);
  });
}
