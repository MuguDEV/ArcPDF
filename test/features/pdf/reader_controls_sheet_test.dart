import 'package:arcpdf/src/features/pdf/viewer/reader_controls_sheet.dart';
import 'package:arcpdf/src/shared/theme/arc_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _filename =
    'An exceptionally long PDF filename with many words and details for reading.pdf';

Finder _action(ReaderAction action) => find.byKey(ValueKey(action));

Future<void> _mount(
  WidgetTester tester, {
  double width = 320,
  double height = 800,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool ready = true,
  bool selected = false,
  int tabCount = 3,
  int page = 7,
  int pageCount = 42,
  bool reducedMotion = false,
  EdgeInsets padding = EdgeInsets.zero,
  ValueChanged<ReaderAction>? onSelected,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.grey,
        brightness: brightness,
      ),
      // Exercise ListTile ink against a nontransparent host theme.
      listTileTheme: ListTileThemeData(
        tileColor: brightness == Brightness.dark
            ? ArcColors.surfaceToken
            : Colors.grey.shade100,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
        accessibleNavigation: reducedMotion,
        padding: padding,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            constraints: BoxConstraints(maxWidth: width),
            builder: (context) => ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height * 0.85),
              child: ReaderControlsSheet(
                title: _filename,
                page: page,
                pageCount: pageCount,
                ready: ready,
                darkPages: selected,
                isFavorite: selected,
                horizontalScroll: selected,
                autoScroll: selected,
                keepAwake: selected,
                fullscreen: selected,
                tabCount: tabCount,
                onSelected: onSelected ?? (_) {},
              ),
            ),
          ),
          child: const Text('Open controls'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open controls'));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, ReaderAction action) async {
  await tester.ensureVisible(_action(action));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 700.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'fits width $width, text ${scale * 100}%, ${brightness.name}',
            (tester) async {
          await _mount(
            tester,
            width: width,
            textScale: scale,
            brightness: brightness,
            reducedMotion: true,
            padding: const EdgeInsets.only(bottom: 24),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Reading controls'), findsOneWidget);
          expect(find.text('Page 7 of 42'), findsOneWidget);
          expect(find.text('View'), findsOneWidget);
          expect(find.text('Reading'), findsOneWidget);
          expect(find.text('Document'), findsOneWidget);
          final filename = tester.widget<Text>(find.text(_filename));
          expect(filename.maxLines, 1);
          expect(filename.overflow, TextOverflow.ellipsis);
          expect(find.byType(Scrollable), findsOneWidget);

          final gridWidth = width - 32;
          final effectiveWidth = gridWidth / scale;
          final columns = effectiveWidth >= 900
              ? 4
              : effectiveWidth >= 520
                  ? 3
                  : 2;
          final viewActions = [
            ReaderAction.pageColors,
            ReaderAction.fitWidth,
            ReaderAction.fitPage,
            ReaderAction.scrollDirection,
            ReaderAction.rotate,
            ReaderAction.fullscreen,
          ];
          final firstRect = tester.getRect(_action(viewActions.first));
          for (var i = 0; i < columns; i++) {
            expect(
                tester.getTopLeft(_action(viewActions[i])).dy, firstRect.top);
          }
          expect(
            tester.getTopLeft(_action(viewActions[columns])).dy,
            greaterThan(firstRect.top),
          );

          for (final action in ReaderAction.values) {
            await _reveal(tester, action);
            final rect = tester.getRect(_action(action));
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(tester.takeException(), isNull, reason: action.name);
          }
          final tabsRect = tester.getRect(_action(ReaderAction.tabs));
          expect(tabsRect.bottom, lessThanOrEqualTo(800 - 24));
        });
      }
    }
  }

  testWidgets(
      'every action delegates once without dismissing or changing state',
      (tester) async {
    final actions = <ReaderAction>[];
    await _mount(tester, onSelected: actions.add);
    for (final action in ReaderAction.values) {
      await _reveal(tester, action);
      await tester.tap(_action(action));
      await tester.pumpAndSettle();
      expect(actions.last, action);
      expect(find.byType(ReaderControlsSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(actions, ReaderAction.values);
    for (final action in [
      ReaderAction.autoScroll,
      ReaderAction.keepAwake,
      ReaderAction.favorite,
    ]) {
      expect(tester.widget<SwitchListTile>(_action(action)).value, isFalse);
    }
  });

  testWidgets(
      'not-ready disables document actions but keeps safe actions usable',
      (tester) async {
    final actions = <ReaderAction>[];
    const available = {
      ReaderAction.pageColors,
      ReaderAction.favorite,
      ReaderAction.keepAwake,
      ReaderAction.info,
      ReaderAction.tabs,
    };
    await _mount(tester, ready: false, onSelected: actions.add);
    expect(find.text('Document not ready'), findsOneWidget);
    for (final action in ReaderAction.values) {
      await _reveal(tester, action);
      final widget = tester.widget(_action(action));
      final enabled = widget is TextButton
          ? widget.onPressed != null
          : (widget as SwitchListTile).onChanged != null;
      expect(enabled, available.contains(action), reason: action.name);
      await tester.tap(_action(action));
      await tester.pumpAndSettle();
    }
    expect(actions.toSet(), available);
    expect(actions, hasLength(available.length));
    expect(find.byType(ReaderControlsSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected states and tooltips reflect inputs', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, selected: true);
      expect(find.byTooltip('Page colors: Dark'), findsOneWidget);
      expect(find.byTooltip('Scroll direction: Horizontal'), findsOneWidget);
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      expect(find.byTooltip('Tabs: 3 open'), findsOneWidget);
      for (final action in [
        ReaderAction.pageColors,
        ReaderAction.scrollDirection,
        ReaderAction.fullscreen,
      ]) {
        await _reveal(tester, action);
        expect(
          tester.getSemantics(_action(action)),
          matchesSemantics(
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
            label: switch (action) {
              ReaderAction.pageColors => 'Page colors',
              ReaderAction.scrollDirection => 'Scroll direction',
              _ => 'Fullscreen',
            },
            tooltip: switch (action) {
              ReaderAction.pageColors => 'Page colors: Dark',
              ReaderAction.scrollDirection => 'Scroll direction: Horizontal',
              _ => 'Exit fullscreen',
            },
          ),
        );
      }
      for (final action in [
        ReaderAction.autoScroll,
        ReaderAction.keepAwake,
        ReaderAction.favorite,
      ]) {
        expect(tester.widget<SwitchListTile>(_action(action)).value, isTrue);
      }
    } finally {
      semantics.dispose();
    }
  });

  for (final tabCount in [0, 1, 2]) {
    testWidgets('tabs shown only for multiple tabs ($tabCount)',
        (tester) async {
      await _mount(tester, tabCount: tabCount);
      expect(_action(ReaderAction.tabs),
          tabCount > 1 ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('close dismisses without selecting an action', (tester) async {
    final actions = <ReaderAction>[];
    await _mount(tester, onSelected: actions.add);
    await tester.tap(find.byTooltip('Close reading controls'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderControlsSheet), findsNothing);
    expect(find.text('Open controls'), findsOneWidget);
    expect(actions, isEmpty);
  });

  testWidgets('keyboard can focus and activate controls', (tester) async {
    final actions = <ReaderAction>[];
    await _mount(tester, onSelected: actions.add, reducedMotion: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.byIcon(Icons.close_rounded))).hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(find.text('Page colors'))).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(actions, [ReaderAction.pageColors]);
    expect(find.byType(ReaderControlsSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short parent constraints still scroll at large text',
      (tester) async {
    await _mount(tester, height: 360, textScale: 2, reducedMotion: true);
    await _reveal(tester, ReaderAction.tabs);
    expect(_action(ReaderAction.tabs).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Close reading controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close reading controls'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderControlsSheet), findsNothing);
  });

  testWidgets('invalid page inputs never display nonsensical page numbers',
      (tester) async {
    await _mount(tester, page: 0, pageCount: 10);
    expect(find.text('Page 1 of 10'), findsOneWidget);
    await _mount(tester, page: 999, pageCount: 10);
    expect(find.text('Page 10 of 10'), findsOneWidget);
    await _mount(tester, pageCount: 0);
    expect(find.text('Document not ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
