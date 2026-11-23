import 'dart:ui' as ui;
import 'dart:io';

import 'package:arcpdf/src/shared/theme/arc_theme.dart';
import 'package:arcpdf/src/theme/arc_typography.dart';

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
import 'package:flutter/foundation.dart';
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
      super.tags,
      {bool preview = false}) {
    const sampleNames = [
      'Design principles',
      'Semester timetable',
      'Project brief',
      'Research notes',
      'Course handbook'
    ];
    final items = List.generate(
        30,
        (index) => PdfFileItem(
              path: '/navigation_test_missing/$index.pdf',
              name: preview
                  ? '${sampleNames[index % sampleNames.length]}.pdf'
                  : 'Document ${index.toString().padLeft(2, '0')}.pdf',
              sizeBytes: preview ? 245760 * (index + 1) : 1024,
              pageCount: preview ? (index + 1) * 6 : null,
              lastModified: preview ? DateTime(2026, 11, 15) : DateTime(2026),
              locationLabel: 'Documents',
              isCorrupted: !preview,
            ));
    state = state.copyWith(
      items: items,
      favorites:
          (preview ? items.where((item) => items.indexOf(item).isEven) : items)
              .map((item) => item.path)
              .toSet(),
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
  bool preview = false,
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
    pdfLibraryControllerProvider.overrideWith((ref) => _Library(
        _Scanner(), favorites, recents, timestamps, tags,
        preview: preview)),
    updaterHttpClientProvider.overrideWithValue(client),
  ]);
  addTearDown(container.dispose);
  return container;
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

  for (final brightness in Brightness.values) {
    testWidgets('shared theme renders primary screens in ${brightness.name}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        final fontDirectory = File(Platform.resolvedExecutable)
            .uri
            .resolve('../../material_fonts/');
        for (final font in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf'
        }.entries) {
          await (FontLoader(font.key)
                ..addFont(Future.value(ByteData.sublistView(
                    await File.fromUri(fontDirectory.resolve(font.value))
                        .readAsBytes()))))
              .load();
        }
      });
      await tester.runAsync(() async {
        final lucide = await rootBundle
            .load('packages/lucide_icons_flutter/assets/lucide.ttf');
        await (FontLoader('packages/lucide_icons_flutter/Lucide')
              ..addFont(SynchronousFuture(lucide)))
            .load();
      });
      final container =
          _shellContainer(preview: true, lowPower: false, blur: false);
      container.read(openTabsProvider.notifier).openTab(
            container.read(pdfLibraryControllerProvider).items.first,
          );
      const capture = ValueKey('themed-shell');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildArcTheme(
              brightness: brightness,
              textTheme: ArcTypography.textTheme(brightness,
                  family: AppFontFamily.system)),
          home: const RepaintBoundary(key: capture, child: AppShell()),
        ),
      ));
      for (final index in [0, 1, 2, 3, 4]) {
        container.read(navigationControllerProvider.notifier).setIndex(index);
        await tester.pumpAndSettle();
        // Let missing-file I/O finish outside the widget test's fake clock,
        // then pump its completion callbacks before taking the sample render.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const previewDir = String.fromEnvironment('ARC_UI_PREVIEW_DIR');
        if (previewDir.isNotEmpty) {
          final boundary =
              tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File('$previewDir/${brightness.name}-$index.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('dock labels and selection fit 3x text in $direction',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = _shellContainer();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              builder: (context, child) => Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(3)),
                      child: child!)),
              home: Consumer(
                  builder: (context, ref, child) => Scaffold(
                      bottomNavigationBar: ArcNavBar(
                          selectedIndex: ref
                              .watch(navigationControllerProvider)
                              .index))))));
      await tester.pumpAndSettle();
      final targets = find.descendant(
          of: find.byType(ArcNavBar), matching: find.byType(InkWell));
      for (var index = 0; index < 5; index++) {
        await tester.tap(targets.at(index));
        await tester.pumpAndSettle();
        final indicator =
            tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
        expect(tester.getCenter(find.byWidget(indicator.child)).dx,
            closeTo(tester.getCenter(targets.at(index)).dx, 0.01));
      }
      for (final text in find
          .descendant(of: find.byType(ArcNavBar), matching: find.byType(Text))
          .evaluate()) {
        expect(
            tester
                .renderObject<RenderParagraph>(find.byWidget(text.widget))
                .didExceedMaxLines,
            isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('actual shell keeps tab ends and FAB above nav at scale $scale',
        (tester) async {
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
        final barRect = tester
            .getRect(find.byKey(const ValueKey('floating-navigation-dock')));
        expect(tester.getRect(scroll).bottom, greaterThan(barRect.top));
        final media = MediaQuery.of(tester.element(page));
        // With extendBody enabled Scaffold exposes the floating dock's
        // footprint through MediaQuery so scroll views can clear it.
        expect(media.padding.bottom, greaterThan(0));
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
      double indicatorTarget(int index) =>
          tester.getCenter(destinations.at(index)).dx -
          tester
                  .getSize(find.byWidget(
                      tester.widget<AnimatedPositioned>(indicator).child))
                  .width /
              2;
      final target = indicatorTarget(4);
      await tester.tap(destinations.at(4));
      await tester.pump();
      final animation = tester.widget<AnimatedPositioned>(indicator);
      expect(animation.curve, Curves.easeOutCubic);
      expect(
          animation.duration,
          disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 300));
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
      expect(indicatorLeft(), closeTo(indicatorTarget(2), 0.001));
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
      expect(ink.borderRadius, const BorderRadius.all(Radius.circular(16)));
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
      testWidgets(
          'dock stays compact and translucent in ${brightness.name}, blur=$blur',
          (tester) async {
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
          final barRect = tester
              .getRect(find.byKey(const ValueKey('floating-navigation-dock')));
          final material = tester.widget<Material>(
              find.byKey(const ValueKey('floating-navigation-dock')));
          expect(material.color!.a, closeTo(0.90, 0.01));
          expect(barRect.width, lessThanOrEqualTo(420));
          expect(
              barRect.width,
              lessThan(tester.view.physicalSize.width /
                  tester.view.devicePixelRatio));
          expect(tester.getRect(find.byType(ToolsScreen)).bottom,
              greaterThan(barRect.top));
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

        // The lightweight dock intentionally lets the surrounding surface
        // influence it without paying for a backdrop blur.
        final overRed = await sampleBar(const Color(0xFFFF0000));
        final overBlue = await sampleBar(const Color(0xFF0000FF));
        expect(overRed, isNot(overBlue));
        expect(
            find.descendant(
                of: find.byType(ArcNavBar),
                matching: find.byType(BackdropFilter)),
            findsNothing);
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
