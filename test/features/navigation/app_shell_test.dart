import 'dart:ui' as ui;

import 'package:arcpdf/src/features/navigation/app_shell.dart';
import 'package:arcpdf/src/features/navigation/arc_nav_bar.dart';
import 'package:arcpdf/src/features/navigation/navigation_controller.dart';
import 'package:arcpdf/src/features/pdf/favorites/favorites_screen.dart';
import 'package:arcpdf/src/features/pdf/home/home_screen.dart';
import 'package:arcpdf/src/features/pdf/recent/recent_screen.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/settings/settings_screen.dart';
import 'package:arcpdf/src/features/tools/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockRef extends Mock implements WidgetRef {}

class _MockContext extends Mock implements BuildContext {}

class _MockBox extends Mock implements Box<dynamic> {}

void main() {
  test('shell lets every tab fill the viewport behind the floating bar', () {
    final ref = _MockRef();
    when(() => ref.watch(splashDoneProvider)).thenReturn(true);
    when(() => ref.watch(navigationControllerProvider))
        .thenReturn(const NavigationState(0));
    // Inspect the shell's actual wrappers without starting scanners, storage,
    // or update checks belonging to its five page widgets.
    final shell = const AppShell().build(_MockContext(), ref) as Scaffold;
    expect(shell.extendBody, isTrue);
    expect(shell.bottomNavigationBar, isA<ArcNavBar>());
    final tabs = (shell.body! as Stack).children.cast<Offstage>().toList();
    expect(tabs.map((tab) => tab.offstage), [false, true, true, true, true]);
    final pages = tabs.map((tab) => (tab.child! as AnimatedOpacity).child);
    expect(pages, [
      isA<HomeScreen>(),
      isA<FavoritesScreen>(),
      isA<RecentScreen>(),
      isA<ToolsScreen>(),
      isA<SettingsScreen>(),
    ]);
  });

  testWidgets('navigation supports large text, keyboard, and low-power mode',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final box = _MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => switch (call.positionalArguments.first) {
              'lowPowerMode' => true,
              'useHaptics' => false,
              _ => call.namedArguments[#defaultValue],
            });
    final container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith((ref) => SettingsController(box)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(bottomNavigationBar: ArcNavBar(selectedIndex: 0)),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
        tester
            .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .duration,
        Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(container.read(navigationControllerProvider).index, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    for (final blur in [false, true]) {
      testWidgets('bar reveals list content in ${brightness.name}, blur=$blur',
          (tester) async {
        final box = _MockBox();
        when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
            .thenAnswer((call) =>
                call.positionalArguments.first == 'useBlurEffect'
                    ? blur
                    : call.namedArguments[#defaultValue]);
        final settings = SettingsController(box);
        const captureKey = ValueKey('navigation-capture');
        const listKey = ValueKey('list');
        final container = ProviderContainer(overrides: [
          settingsControllerProvider.overrideWith((ref) => settings),
        ]);
        addTearDown(container.dispose);

        Future<Color> sampleBar(Color itemColor) async {
          await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: RepaintBoundary(
                key: captureKey,
                child: Scaffold(
                  extendBody: true,
                  body: ListView.builder(
                    key: listKey,
                    padding: const EdgeInsets.only(bottom: 140),
                    itemCount: 30,
                    itemBuilder: (context, index) => Container(
                      height: 100,
                      color: itemColor,
                    ),
                  ),
                  bottomNavigationBar: const ArcNavBar(selectedIndex: 0),
                ),
              ),
            ),
          ));
          await tester.pump(const Duration(seconds: 1));
          final barRect = tester.getRect(find.descendant(
            of: find.byType(ArcNavBar),
            matching: find.byType(ClipRRect),
          ));
          expect(tester.getRect(find.byKey(listKey)).bottom,
              greaterThan(barRect.bottom));
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          final sample = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
              final offset = ((barRect.top + 4).round() * image.width +
                      barRect.center.dx.round()) *
                  4;
              return Color.fromARGB(255, pixels.getUint8(offset),
                  pixels.getUint8(offset + 1), pixels.getUint8(offset + 2));
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
          return sample!;
        }

        // The tint must retain the color of real content beneath it, not just
        // paint the same surface color over both backgrounds.
        final overRed = await sampleBar(const Color(0xFFFF0000));
        final overBlue = await sampleBar(const Color(0xFF0000FF));
        expect(overRed.r, greaterThan(overRed.b));
        expect(overBlue.b, greaterThan(overBlue.r));
        expect(overRed, isNot(overBlue));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
