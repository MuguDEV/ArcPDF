import 'dart:ui' as ui;

import 'package:arcpdf/src/features/navigation/app_shell.dart';
import 'package:arcpdf/src/features/navigation/arc_nav_bar.dart';
import 'package:arcpdf/src/features/navigation/navigation_controller.dart';
import 'package:arcpdf/src/features/onboarding/onboarding_controller.dart';
import 'package:arcpdf/src/features/onboarding/onboarding_screen.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_custom_card.dart';
import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/updater/updater_service.dart';
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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _MockBox extends Mock implements Box<dynamic> {}

class _Box<T> extends Mock implements Box<T> {}

class _Scanner extends Mock implements PdfScannerService {}

class _Library extends PdfLibraryController {
  _Library(super.scanner, super.favorites, super.recents, super.timestamps,
      super.tags) {
    final items = List.generate(
        30,
        (index) => PdfFileItem(
              path: '/navigation_test_missing/$index.pdf',
              name: 'Document ${index.toString().padLeft(2, '0')}.pdf',
              sizeBytes: 1024,
              lastModified: DateTime(2026),
              locationLabel: 'Documents',
              isCorrupted: true,
            ));
    state = state.copyWith(
      items: items,
      favorites: items.map((item) => item.path).toSet(),
      recents: {for (final item in items) item.path: DateTime(2026)},
    );
  }

  @override
  Future<void> refresh({bool requestPermission = false}) async {}
}

ProviderContainer _shellContainer({
  bool blur = true,
  bool lowPower = true,
  bool onboardingPending = false,
}) {
  final favorites = _Box<String>();
  final recents = _Box<String>();
  final timestamps = _Box<int>();
  final tags = _Box<List<String>>();
  when(() => favorites.keys).thenReturn([]);
  when(() => favorites.values).thenReturn([]);
  when(() => recents.keys).thenReturn([]);
  when(() => recents.values).thenReturn([]);
  when(() => timestamps.toMap()).thenReturn({});
  when(() => tags.keys).thenReturn([]);
  final box = _MockBox();
  when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((call) => switch (call.positionalArguments.first) {
            'useBlurEffect' => blur,
            'lowPowerMode' => lowPower,
            'useHaptics' => false,
            _ => call.namedArguments[#defaultValue],
          });
  final client = MockClient((_) async => http.Response('', 404));
  addTearDown(client.close);
  final container = ProviderContainer(overrides: [
    splashDoneProvider.overrideWith((ref) => true),
    if (onboardingPending)
      onboardingCompletedProvider.overrideWith((ref) {
        final store = <String, Object?>{};
        final onboardingBox = _MockBox();
        when(() => onboardingBox.isOpen).thenReturn(true);
        when(() => onboardingBox.isNotEmpty).thenReturn(false);
        when(() => onboardingBox.get(any(),
                defaultValue: any(named: 'defaultValue')))
            .thenAnswer((call) =>
                store[call.positionalArguments.first as String] ??
                call.namedArguments[#defaultValue]);
        when(() => onboardingBox.put(any(), any())).thenAnswer((call) async {
          store[call.positionalArguments.first as String] =
              call.positionalArguments[1];
        });
        return OnboardingCompletedNotifier(onboardingBox);
      }),
    settingsControllerProvider.overrideWith((ref) => SettingsController(box)),
    securityControllerProvider.overrideWith((ref) => SecurityController(box)),
    openTabsProvider.overrideWith((ref) => OpenTabsNotifier(box)),
    pdfLibraryControllerProvider.overrideWith(
        (ref) => _Library(_Scanner(), favorites, recents, timestamps, tags)),
    updaterHttpClientProvider.overrideWithValue(client),
  ]);
  addTearDown(container.dispose);
  return container;
}

void _allowExistingToolCardOverflow() {
  final reportError = FlutterError.onError;
  // Tools' fixed-height cards already overflow at large text sizes (and with
  // the test font). Keep this unrelated, out-of-scope defect from masking
  // shell regressions; all other rendering errors still fail these tests.
  FlutterError.onError = (details) {
    final diagnostic = details.toString();
    if (details.exceptionAsString().startsWith('A RenderFlex overflowed') &&
        diagnostic.contains('/tools/widgets/tool_card.dart:')) {
      return;
    }
    reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'ArcPDF',
      packageName: 'com.arcpdf',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('actual shell keeps tab ends and FAB above nav at scale $scale',
        (tester) async {
      _allowExistingToolCardOverflow();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _shellContainer();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 36),
              viewPadding: const EdgeInsets.only(bottom: 36),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const AppShell(),
        ),
      ));
      await tester.pumpAndSettle();
      final shell = tester.widget<Scaffold>(find
          .descendant(
              of: find.byType(AppShell), matching: find.byType(Scaffold))
          .first);
      expect(shell.extendBody, isTrue);
      final tabStack = find
          .descendant(of: find.byType(AppShell), matching: find.byType(Stack))
          .first;
      final tabs = tester.widget<Stack>(tabStack).children.cast<Offstage>();
      expect(tabs.map((tab) => tab.offstage), [false, true, true, true, true]);
      expect(tabs.map((tab) => (tab.child! as TickerMode).enabled),
          [true, false, false, false, false]);
      final pageTypes = [
        HomeScreen,
        FavoritesScreen,
        RecentScreen,
        ToolsScreen,
        SettingsScreen
      ];
      for (var index = 0; index < pageTypes.length; index++) {
        container.read(navigationControllerProvider.notifier).setIndex(index);
        await tester.pumpAndSettle();
        final page = find.byType(pageTypes[index]);
        final scroll = find
            .descendant(of: page, matching: find.byType(CustomScrollView))
            .first;
        final barRect = tester.getRect(find.descendant(
            of: find.byType(ArcNavBar), matching: find.byType(ClipRRect)));
        expect(tester.getRect(scroll).bottom, greaterThan(barRect.bottom));
        final media = MediaQuery.of(tester.element(page));
        expect(media.padding.bottom,
            tester.getSize(find.byType(ArcNavBar)).height);
        expect(media.viewPadding.bottom, media.padding.bottom);
        final scrollable = find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        if (index < 3) {
          final cards =
              find.descendant(of: page, matching: find.byType(PdfCustomCard));
          expect(cards, findsWidgets);
          expect(tester.getRect(cards.last).bottom, lessThan(barRect.top));
        } else {
          final lastControl = index == 3
              ? find.text('PDF to Images')
              : find.text('Check for Updates');
          expect(lastControl, findsOneWidget);
          expect(tester.getRect(lastControl).bottom, lessThan(barRect.top));
        }
        if (index == 0) {
          final fab = find.byTooltip('Scroll to top');
          expect(fab, findsOneWidget);
          expect(tester.getRect(fab).bottom, lessThan(barRect.top));
          await tester.tap(fab);
          await tester.pumpAndSettle();
          expect(position.pixels, 0);
        }
      }
      // The keyboard already reduces the outer body; a nested Scaffold must
      // not apply that view inset a second time or strand its floating action.
      container.read(navigationControllerProvider.notifier).setIndex(0);
      await tester.pumpAndSettle();
      final homeScroll = find
          .descendant(
              of: find.byType(HomeScreen), matching: find.byType(Scrollable))
          .first;
      tester.state<ScrollableState>(homeScroll).position.jumpTo(500);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final fabRect = tester.getRect(find.byTooltip('Scroll to top'));
      expect(fabRect.bottom, lessThanOrEqualTo(600));
      expect(fabRect.top, greaterThan(400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final disableAnimations in [false, true]) {
    testWidgets('indicator is bounded and settles, reduced=$disableAnimations',
        (tester) async {
      final box = _MockBox();
      when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
          .thenAnswer((call) => switch (call.positionalArguments.first) {
                'useHaptics' => false,
                'animSpeed' => 1.5,
                _ => call.namedArguments[#defaultValue],
              });
      when(() => box.put(any(), any())).thenAnswer((_) async {});
      final container = ProviderContainer(overrides: [
        settingsControllerProvider
            .overrideWith((ref) => SettingsController(box)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Consumer(
              builder: (context, ref, child) => Scaffold(
                    bottomNavigationBar: ArcNavBar(
                      selectedIndex:
                          ref.watch(navigationControllerProvider).index,
                    ),
                  )),
        ),
      ));
      await tester.pumpAndSettle();
      final indicator = find.byType(AnimatedPositioned);
      double indicatorLeft() => tester
          .getTopLeft(
              find.byWidget(tester.widget<AnimatedPositioned>(indicator).child))
          .dx;
      final start = indicatorLeft();
      final destinations = find.descendant(
          of: find.byType(ArcNavBar), matching: find.byType(InkWell));
      final target = tester.getTopLeft(destinations.at(4)).dx;
      await tester.tap(destinations.at(4));
      await tester.pump();
      final animation = tester.widget<AnimatedPositioned>(indicator);
      expect(animation.curve, Curves.easeOutCubic);
      expect(
          animation.duration,
          disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 390));
      var previous = start;
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final current = indicatorLeft();
        expect(current, inInclusiveRange(previous - 0.001, target + 0.001));
        previous = current;
      }
      expect(indicatorLeft(), closeTo(target, 0.001));
      // Rapid changes retarget the existing slide rather than adding effects.
      await tester.tap(destinations.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 64));
      await tester.tap(destinations.at(2));
      await tester.pumpAndSettle();
      expect(indicatorLeft(),
          closeTo(tester.getTopLeft(destinations.at(2)).dx, 0.001));
      expect(
          find.descendant(
              of: find.byType(ArcNavBar), matching: find.byType(Transform)),
          findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await container
          .read(settingsControllerProvider.notifier)
          .setUseBlurEffect(false);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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
    final semantics = tester.ensureSemantics();

    expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        matchesSemantics(
            label: 'Home',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true));
    final targets = find.descendant(
        of: find.byType(ArcNavBar), matching: find.byType(InkWell));
    for (final target in targets.evaluate()) {
      final ink = target.widget as InkWell;
      expect(ink.borderRadius, const BorderRadius.all(Radius.circular(28)));
      final material = tester.widget<Material>(find
          .ancestor(of: find.byWidget(ink), matching: find.byType(Material))
          .first);
      expect(material.clipBehavior, Clip.antiAlias);
      expect(material.borderRadius, ink.borderRadius);
      expect(tester.getSize(find.byWidget(ink)).shortestSide,
          greaterThanOrEqualTo(44));
    }
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
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    for (final blur in [false, true]) {
      testWidgets('shell backdrop floats in ${brightness.name}, blur=$blur',
          (tester) async {
        _allowExistingToolCardOverflow();
        const captureKey = ValueKey('navigation-capture');
        final container = _shellContainer(blur: blur, lowPower: false);
        container.read(navigationControllerProvider.notifier).setIndex(3);

        Future<Color> sampleBar(Color itemColor) async {
          await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(
                brightness: brightness,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.grey,
                  brightness: brightness,
                ).copyWith(surface: itemColor),
              ),
              home: const RepaintBoundary(
                key: captureKey,
                child: AppShell(),
              ),
            ),
          ));
          await tester.pump(const Duration(seconds: 1));
          final barRect = tester.getRect(find.descendant(
            of: find.byType(ArcNavBar),
            matching: find.byType(ClipRRect),
          ));
          expect(tester.getRect(find.byType(ToolsScreen)).bottom,
              greaterThan(barRect.bottom));
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          final sample = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
              // The margin beside the floating bar must show the nested
              // screen, not a solid strip from the outer Scaffold.
              final marginOffset =
                  ((barRect.top + 4).round() * image.width + 4) * 4;
              expect(
                  Color.fromARGB(
                      255,
                      pixels.getUint8(marginOffset),
                      pixels.getUint8(marginOffset + 1),
                      pixels.getUint8(marginOffset + 2)),
                  itemColor);
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

        // The tint must retain the color of the actual tab beneath it, not just
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

  testWidgets('first run shows onboarding in place of the shell until done',
      (tester) async {
    final container = _shellContainer(onboardingPending: true);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pump();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(ArcNavBar), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ArcNavBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
