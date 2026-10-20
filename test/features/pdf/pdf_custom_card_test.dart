import 'dart:io';

import 'package:flutter/services.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_custom_card.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _Box<T> extends Mock implements Box<T> {}

class _Scanner extends Mock implements PdfScannerService {}

class _Library extends PdfLibraryController {
  _Library(super.scanner, super.favorites, super.recents, super.timestamps,
      super.tags);

  @override
  Future<void> refresh({bool requestPermission = false}) async {}
}

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
  late ProviderContainer container;
  late SettingsController settings;
  var taps = 0;
  var favorites = 0;
  var vaults = 0;

  setUp(() {
    final favoriteBox = _Box<String>();
    final recents = _Box<String>();
    final timestamps = _Box<int>();
    final tags = _Box<List<String>>();
    when(() => favoriteBox.keys).thenReturn([]);
    when(() => recents.keys).thenReturn([]);
    when(() => favoriteBox.values).thenReturn([]);
    when(() => recents.values).thenReturn([]);
    when(() => timestamps.toMap()).thenReturn({});
    when(() => tags.keys).thenReturn([]);
    final box = _Box<dynamic>();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => switch (call.positionalArguments.first) {
              'enableGyroCards' => false,
              'useHaptics' => false,
              _ => call.namedArguments[#defaultValue],
            });
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    settings = SettingsController(box);
    container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith((ref) => settings),
      pdfLibraryControllerProvider.overrideWith((ref) =>
          _Library(_Scanner(), favoriteBox, recents, timestamps, tags)),
    ]);
    taps = favorites = vaults = 0;
  });
  tearDown(() => container.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool selection = false,
    bool selected = false,
    bool vault = false,
    bool disableAnimations = false,
    bool longContent = false,
    Brightness brightness = Brightness.light,
    int cardCount = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: brightness == Brightness.light
                ? const ColorScheme.light(
                    primary: Colors.black, primaryContainer: Color(0xffeeeeee))
                : const ColorScheme.dark(
                    primary: Colors.white,
                    primaryContainer: Color(0xff333333))),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
          for (var index = 0; index < cardCount; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PdfCustomCard(
                key: ValueKey('card_$index'),
                item: PdfFileItem(
                  path: '/missing/card.pdf',
                  name: longContent
                      ? 'Quarterly financial report and supporting documents.pdf'
                      : 'Report.pdf',
                  locationLabel: longContent
                      ? 'Documents / Reports / Annual archive'
                      : 'Documents',
                  sizeBytes: 2048,
                  lastModified: DateTime(2026, 10, 19, 10, 30),
                ),
                index: index,
                selectionMode: selection,
                selected: selected,
                onTap: () => taps++,
                onFavorite: () => favorites++,
                onVault: vault ? () => vaults++ : null,
              ),
            ),
        ])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        find.descendant(
            of: find.byType(PdfCustomCard),
            matching: find.byType(BackdropFilter)),
        findsNothing);
  }

  Finder surface(Finder card) => find.descendant(
        of: card,
        matching: find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).border?.top.width == 1.5),
      );

  for (final mode in ['animated', 'reduced motion', 'eco']) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('$mode: actual card heights match at ${scale}x',
          (tester) async {
        await settings.setLowPowerMode(mode == 'eco');
        for (final vault in [false, true]) {
          final heights = <double>[];
          for (final brightness in Brightness.values) {
            for (final state in [(false, false), (true, false), (true, true)]) {
              await mount(tester,
                  scale: scale,
                  vault: vault,
                  brightness: brightness,
                  disableAnimations: mode == 'reduced motion',
                  selection: state.$1,
                  selected: state.$2);
              heights.add(tester.getSize(find.byType(PdfCustomCard)).height);
            }
          }
          for (final height in heights) {
            expect(height, closeTo(heights.first, 0.01));
          }
          expect(heights.first, inInclusiveRange(96, scale == 1 ? 132 : 308));
        }
      });
    }
  }

  testWidgets('narrow large text wraps title and location without clipping',
      (tester) async {
    await mount(tester, width: 320, scale: 3, longContent: true);
    final height = tester.getSize(find.byType(PdfCustomCard)).height;
    expect(height, inInclusiveRange(300, 1000));
    for (final text in [
      'Quarterly financial report and supporting documents',
      'Documents / Reports / Annual archive',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.height, greaterThan(40));
    }
    await mount(tester,
        width: 320,
        scale: 3,
        longContent: true,
        selection: true,
        selected: true);
    expect(tester.getSize(find.byType(PdfCustomCard)).height,
        closeTo(height, 0.01));
  });

  testWidgets('solid scheme surfaces do not blur with either blur preference',
      (tester) async {
    await settings.setLowPowerMode(false);
    for (final blur in [false, true]) {
      await settings.setUseBlurEffect(blur);
      for (final brightness in Brightness.values) {
        for (final selected in [false, true]) {
          await mount(tester,
              brightness: brightness, selection: selected, selected: selected);
          final card = find.byType(PdfCustomCard);
          final scheme = Theme.of(tester.element(card)).colorScheme;
          final decoration = tester.widget<Container>(surface(card)).decoration!
              as BoxDecoration;
          expect(decoration.color,
              selected ? scheme.primaryContainer : scheme.surfaceContainerLow);
          expect(decoration.color!.a, 1);
        }
      }
    }
  });

  testWidgets('caller spacing produces a single 10px surface gap',
      (tester) async {
    for (final reduced in [false, true]) {
      for (final selection in [false, true]) {
        await mount(tester,
            cardCount: 2,
            disableAnimations: reduced,
            selection: selection,
            selected: selection);
        final first = find.byKey(const ValueKey('card_0'));
        final second = find.byKey(const ValueKey('card_1'));
        final firstSurface = tester.getRect(surface(first));
        final secondSurface = tester.getRect(surface(second));
        expect(tester.getRect(first), firstSurface);
        expect(secondSurface.top - firstSurface.bottom, closeTo(10, 0.01));
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('swipe actions keep callbacks and scheme colors in $brightness',
        (tester) async {
      await settings.setLowPowerMode(false);
      await mount(tester, brightness: brightness, vault: true);
      await tester.drag(find.byType(PdfCustomCard), const Offset(-220, 0));
      await tester.pumpAndSettle();
      final vaultIcon = find.byIcon(HugeIcons.strokeRoundedSafe);
      expect(vaultIcon.hitTestable(), findsOneWidget);
      final scheme = Theme.of(tester.element(vaultIcon)).colorScheme;
      final vaultSurface = find
          .ancestor(
              of: vaultIcon,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container && widget.decoration is BoxDecoration))
          .first;
      final decoration =
          tester.widget<Container>(vaultSurface).decoration! as BoxDecoration;
      expect(decoration.color, scheme.surfaceContainerHigh);
      expect(tester.widget<Icon>(vaultIcon).color, scheme.onSurface);
      await tester.tap(vaultIcon);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PdfCustomCard), const Offset(220, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(vaults, 1);
      expect(favorites, 1);
      expect(taps, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact controls retain 44px targets and separate actions',
      (tester) async {
    await mount(tester, vault: true, disableAnimations: true);
    for (final tooltip in ['Add to favorites', 'Move to Secure Vault']) {
      final button = find.byTooltip(tooltip);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tapAt(tester.getTopLeft(button) + const Offset(2, 2));
      await tester.pumpAndSettle();
    }
    expect(favorites, 1);
    expect(vaults, 1);
    expect(taps, 0);
    await mount(tester, selection: true, selected: true);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
