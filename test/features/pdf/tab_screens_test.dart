import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/viewer/multi_tab_viewer_screen.dart';
import 'package:arcpdf/src/features/pdf/viewer/tab_switcher_screen.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/shared/theme/arc_colors.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBox extends Mock implements Box<dynamic> {}

class _TestViewer extends StatefulWidget {
  const _TestViewer({required this.item});
  final PdfFileItem item;

  @override
  State<_TestViewer> createState() => _TestViewerState();
}

class _TestViewerState extends State<_TestViewer> {
  late final initialPath = widget.item.path;

  @override
  Widget build(BuildContext context) => Text(widget.item.name);
}

Widget _buildViewer(BuildContext context, PdfFileItem item) =>
    _TestViewer(item: item);

PdfFileItem _item(String name) => PdfFileItem(
      path: '/arcpdf_tab_tests_missing/$name.pdf',
      name: '$name.pdf',
      sizeBytes: 10,
      lastModified: DateTime(2026),
      locationLabel: 'Tabs',
    );

void main() {
  late OpenTabsNotifier tabs;
  late ProviderContainer container;

  setUp(() {
    final box = _MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    tabs = OpenTabsNotifier(box);
    final settings = SettingsController(box);
    container = ProviderContainer(overrides: [
      openTabsProvider.overrideWith((ref) => tabs),
      settingsControllerProvider.overrideWith((ref) => settings),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> pumpScreen(WidgetTester tester, Widget screen,
      {bool reducedMotion = true,
      double width = 800,
      double textScale = 1,
      Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: screen,
      ),
    ));
    await tester.pump();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  PageController pageController(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!;

  Finder viewerFor(PdfFileItem item) => find.descendant(
      of: find.byKey(ValueKey(item.path)), matching: find.byType(_TestViewer));

  const viewer = MultiTabViewerScreen(viewerBuilder: _buildViewer);

  testWidgets('earlier removal preserves active path, page, and viewer state',
      (tester) async {
    final a = _item('a');
    final b = _item('b');
    final c = _item('c');
    for (final item in [a, b, c]) {
      tabs.openTab(item);
    }
    tabs.setActiveIndex(1);
    await pumpScreen(tester, viewer);
    final bState = tester.state(viewerFor(b));
    tabs.closeTab(0);
    await tester.pump();
    await tester.pump();
    expect(tabs.state.tabs[tabs.state.activeIndex].path, b.path);
    expect(pageController(tester).page, 0);
    expect(tester.state(viewerFor(b)), same(bState));
    expect(tester.widget<_TestViewer>(viewerFor(b)).item.path, b.path);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('removing active first tab does not reuse its viewer state',
      (tester) async {
    final a = _item('a');
    final b = _item('b');
    tabs.openTab(a);
    tabs.openTab(b);
    tabs.setActiveIndex(0);
    await pumpScreen(tester, viewer);
    final aState = tester.state(viewerFor(a));
    tabs.closeTab(0);
    await tester.pump();
    await tester.pump();
    expect(tabs.state.tabs.single.path, b.path);
    expect(pageController(tester).page, 0);
    expect(tester.state(viewerFor(b)), isNot(same(aState)));
    expect(aState.mounted, isFalse);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('inactive viewers are released without reusing their state',
      (tester) async {
    final a = _item('a');
    tabs.openTab(a);
    tabs.openTab(_item('b'));
    tabs.openTab(_item('c'));
    tabs.setActiveIndex(0);
    await pumpScreen(tester, viewer);
    final aState = tester.state(viewerFor(a));
    tabs.setActiveIndex(2);
    await tester.pump();
    await tester.pump();
    expect(aState.mounted, isFalse);
    tabs.setActiveIndex(0);
    await tester.pump();
    await tester.pump();
    final restoredState = tester.state<_TestViewerState>(viewerFor(a));
    expect(restoredState, isNot(same(aState)));
    expect(restoredState.initialPath, a.path);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('rapid removals and selections sync only the latest state',
      (tester) async {
    for (final name in ['a', 'b', 'c', 'd']) {
      tabs.openTab(_item(name));
    }
    await pumpScreen(tester, viewer);
    tabs.setActiveIndex(0);
    tabs.closeTab(0);
    tabs.setActiveIndex(2);
    tabs.closeTab(0);
    await tester.pump();
    await tester.pump();
    expect(tabs.state.tabs[tabs.state.activeIndex].name, 'd.pdf');
    expect(pageController(tester).page, 1);
    tabs.setActiveIndex(0);
    tabs.setActiveIndex(1);
    await disposeScreen(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic selection skips intermediate active documents',
      (tester) async {
    for (final name in ['a', 'b', 'c', 'd']) {
      tabs.openTab(_item(name));
    }
    tabs.setActiveIndex(0);
    await pumpScreen(tester, viewer);
    final selections = <int>[];
    final subscription = container.listen(
        openTabsProvider, (previous, next) => selections.add(next.activeIndex));
    tabs.setActiveIndex(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(pageController(tester).page, 3);
    expect(selections, [3]);
    subscription.close();
    await disposeScreen(tester);
  });

  testWidgets('stale page callbacks cannot change selection after a removal',
      (tester) async {
    for (final name in ['a', 'b', 'c']) {
      tabs.openTab(_item(name));
    }
    await pumpScreen(tester, viewer);
    final oldPageView = tester.widget<PageView>(find.byType(PageView));
    tabs.closeTab(0);
    oldPageView.onPageChanged!(0);
    expect(tabs.state.activeIndex, 1);
    expect(tabs.state.tabs[1].name, 'c.pdf');
    await tester.pump();
    await tester.pump();
    expect(pageController(tester).page, 1);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('opening tabs before controller attachment uses latest selection',
      (tester) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tabs.openTab(_item('a'));
      tabs.openTab(_item('b'));
    });
    await pumpScreen(tester, viewer);
    await tester.pump();
    await tester.pump();
    expect(tabs.state.activeIndex, 1);
    expect(pageController(tester).page, 1);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('closing the last tab returns viewer and switcher to home',
      (tester) async {
    tabs.openTab(_item('a'));
    await pumpScreen(tester, const Scaffold(body: Text('Home')));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => viewer));
    await tester.pumpAndSettle();
    navigator.push(
        MaterialPageRoute<void>(builder: (_) => const TabSwitcherScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close a.pdf'));
    await tester.pumpAndSettle();
    expect(tabs.state.tabs, isEmpty);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(MultiTabViewerScreen), findsNothing);
    expect(find.byType(TabSwitcherScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('user swipes still update the active tab', (tester) async {
    tabs.openTab(_item('a'));
    tabs.openTab(_item('b'));
    tabs.setActiveIndex(0);
    await pumpScreen(tester, viewer);
    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(tabs.state.activeIndex, 1);
    expect(pageController(tester).page, 1);
    await disposeScreen(tester);
  });

  for (final width in [320.0, 700.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('switcher fits $width with large text in $brightness',
          (tester) async {
        tabs.openTab(
            _item('A very long document title for responsive testing'));
        tabs.openTab(_item('b'));
        await pumpScreen(tester, const TabSwitcherScreen(),
            width: width, textScale: 2, brightness: brightness);
        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(
            delegate.crossAxisCount, width == 320 ? 1 : (width == 700 ? 2 : 4));
        final context = tester.element(find.byType(TabSwitcherScreen));
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, ArcColors.surface(context));
        expect(tester.takeException(), isNull);
        await disposeScreen(tester);
      });
    }
  }

  testWidgets('close controls are labeled, touch sized, and do not select tabs',
      (tester) async {
    tabs.openTab(_item('a'));
    tabs.openTab(_item('b'));
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, const TabSwitcherScreen());
    final close = find.byTooltip('Close a.pdf');
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));

    expect(find.bySemanticsLabel('Close a.pdf'), findsOneWidget);
    expect(find.bySemanticsLabel('Switch to b.pdf'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(close);
    await tester.pump();
    expect(tabs.state.tabs.single.name, 'b.pdf');
    expect(tabs.state.activeIndex, 0);
    expect(find.byType(TabSwitcherScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await disposeScreen(tester);
  });

  testWidgets('keyboard can focus and activate close controls', (tester) async {
    tabs.openTab(_item('a'));
    tabs.openTab(_item('b'));
    await pumpScreen(tester, const TabSwitcherScreen());
    final closeIcon = find.descendant(
        of: find.byTooltip('Close a.pdf'), matching: find.byType(Icon));
    final focus = Focus.of(tester.element(closeIcon));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tabs.state.tabs.single.name, 'b.pdf');
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('reduced motion skips switcher entrance effects', (tester) async {
    tabs.openTab(_item('a'));
    await pumpScreen(tester, const TabSwitcherScreen());
    expect(find.byType(Animate), findsNothing);
    await pumpScreen(tester, const TabSwitcherScreen(), reducedMotion: false);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(Animate), findsOneWidget);
    await tester.pumpAndSettle();
    await disposeScreen(tester);
  });

  testWidgets('empty switcher offers a home action', (tester) async {
    await pumpScreen(tester, const TabSwitcherScreen());
    expect(find.text('No open tabs'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Go Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });
}
