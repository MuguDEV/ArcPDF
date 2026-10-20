import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/navigation/arc_nav_bar.dart';
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/home/home_screen.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_custom_card.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_card_shimmer.dart';
import 'package:arcpdf/src/shared/widgets/empty_state.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/tools/pages/merge_pdfs_page.dart';
import 'package:arcpdf/src/features/updater/updater_service.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Box<T> extends Mock implements Box<T> {}

class _Scanner extends Mock implements PdfScannerService {}

class _Library extends PdfLibraryController {
  _Library(super.scanner, super.favorites, super.recents, super.timestamps,
      super.tags, List<PdfFileItem> items) {
    state = state.copyWith(items: items);
  }
  final deleted = <String>[];
  final favoriteCalls = <String>[];
  final failures = <String>{};
  final favoriteFailures = <String>{};
  Completer<bool>? pendingDelete;

  @override
  Future<void> refresh({bool requestPermission = false}) async {}

  @override
  Future<void> toggleFavorite(PdfFileItem item) {
    favoriteCalls.add(item.path);
    if (favoriteFailures.contains(item.path)) {
      return Future<void>.error(StateError('Favorite unavailable'));
    }
    final favorites = {...state.favorites};
    if (!favorites.remove(item.path)) favorites.add(item.path);
    state = state.copyWith(favorites: favorites);
    return Future<void>.value();
  }

  @override
  Future<bool> deleteFile(PdfFileItem item) async {
    deleted.add(item.path);
    final success = pendingDelete != null
        ? await pendingDelete!.future
        : !failures.contains(item.path);
    if (success) {
      state = state.copyWith(
          items: state.items.where((file) => file.path != item.path).toList());
    }
    return success;
  }

  void replaceItems(List<PdfFileItem> items) =>
      state = state.copyWith(items: items);

  void replaceTags(Map<String, List<String>> tags) =>
      state = state.copyWith(tags: tags);

  void setLoading(bool loading) => state = state.copyWith(loading: loading);
}

PdfFileItem _item(String name, {String? path}) => PdfFileItem(
      path: path ?? '/arcpdf_home_missing/$name.pdf',
      name: '$name.pdf',
      sizeBytes: 1024,
      lastModified: DateTime(2026),
      locationLabel: 'Documents',
      isCorrupted: true,
    );

void main() {
  late _Library library;
  late ProviderContainer container;
  late OpenTabsNotifier tabs;
  late List<PdfFileItem> items;
  late bool lowPowerMode;

  setUp(() {
    lowPowerMode = true;
    items = [_item('Alpha'), _item('Beta'), _item('Gamma')];
    final favorites = _Box<String>();
    final recents = _Box<String>();
    final timestamps = _Box<int>();
    final tags = _Box<List<String>>();
    when(() => favorites.keys).thenReturn([]);
    when(() => favorites.values).thenReturn([items.first.path]);
    when(() => favorites.put(any(), any())).thenAnswer((_) async {});
    when(() => favorites.delete(any())).thenAnswer((_) async {});
    when(() => recents.keys).thenReturn([]);
    when(() => recents.values).thenReturn([]);
    when(() => timestamps.toMap()).thenReturn({});
    when(() => tags.keys).thenReturn([]);
    library = _Library(_Scanner(), favorites, recents, timestamps, tags, items);
    final session = _Box<dynamic>();
    when(() => session.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => switch (call.positionalArguments.first) {
              'lowPowerMode' => lowPowerMode,
              'useHaptics' => false,
              _ => call.namedArguments[#defaultValue],
            });
    when(() => session.put(any(), any())).thenAnswer((_) async {});
    tabs = OpenTabsNotifier(session);
    final client = MockClient((_) async => http.Response('', 404));
    container = ProviderContainer(overrides: [
      pdfLibraryControllerProvider.overrideWith((ref) => library),
      settingsControllerProvider
          .overrideWith((ref) => SettingsController(session)),
      openTabsProvider.overrideWith((ref) => tabs),
      updaterHttpClientProvider.overrideWithValue(client),
    ]);
    addTearDown(client.close);
    PackageInfo.setMockInitialValues(
        appName: 'ArcPDF',
        packageName: 'com.arcpdf',
        version: '1.4.4',
        buildNumber: '1',
        buildSignature: '');
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester,
      {double scale = 1,
      double width = 400,
      bool disableAnimations = true,
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
              textScaler: TextScaler.linear(scale),
              disableAnimations: disableAnimations,
              padding: const EdgeInsets.only(bottom: 24)),
          child: child!,
        ),
        home: const Scaffold(
            body: HomeScreen(),
            bottomNavigationBar: ArcNavBar(selectedIndex: 0)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder card(String name) => find.byWidgetPredicate(
      (widget) => widget is PdfCustomCard && widget.item.name == '$name.pdf');

  Future<void> select(WidgetTester tester) async {
    await tester.longPress(card('Alpha'));
    await tester.pumpAndSettle();
  }

  Finder selectedCount(int count) => find.byWidgetPredicate((widget) =>
      widget is Text &&
      widget.key == const ValueKey('home-selection-count') &&
      widget.data == '$count');

  Future<void> overflowAction(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('More selection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  IconButton action(WidgetTester tester, String label) =>
      tester.widget<IconButton>(find.widgetWithIcon(
          IconButton,
          switch (label) {
            'Share' => Icons.share_outlined,
            _ => Icons.more_horiz_rounded,
          }));

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'selection is a small in-flow checked control with keyboard support',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    await select(tester);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.getSize(find.byIcon(Icons.check_circle_rounded)),
        const Size(44, 44));
    expect(find.byType(Animate), findsNothing);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Alpha.pdf')),
        matchesSemantics(
            label: 'Alpha.pdf',
            isButton: true,
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true));
    final ink =
        find.descendant(of: card('Beta'), matching: find.byType(InkWell));
    final indicator = find.descendant(
        of: ink, matching: find.byIcon(Icons.radio_button_unchecked_rounded));
    Focus.of(tester.element(indicator)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<PdfCustomCard>(card('Beta')).selected, isTrue);
    expect(selectedCount(2), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await disposeScreen(tester);
  });

  testWidgets(
      'select all uses filtered results and clear preserves selection mode',
      (tester) async {
    await mount(tester);
    await select(tester);
    library.setQuery('Beta');
    await tester.pumpAndSettle();
    await overflowAction(tester, 'Select all');
    await tester.pump();
    expect(selectedCount(2), findsOneWidget);
    await overflowAction(tester, 'Clear selection');
    await tester.pump();
    expect(selectedCount(0), findsOneWidget);
    expect(action(tester, 'Share').onPressed, isNull);
    await tester.tap(find.byTooltip('Exit selection'));
    await tester.pump();
    expect(selectedCount(0), findsNothing);
    await disposeScreen(tester);
  });

  for (final enabled in [false, true]) {
    testWidgets('bulk favorites emit one preference-aware cue: $enabled',
        (tester) async {
      await mount(tester);
      await select(tester);
      await tester.tap(card('Beta'));
      await tester.pump();
      await container
          .read(settingsControllerProvider.notifier)
          .setUseHaptics(enabled);
      final feedback = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') feedback.add(call);
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byTooltip('Favorite'));
      await tester.pumpAndSettle();
      expect(feedback, hasLength(enabled ? 1 : 0));
      feedback.clear();
      await tester.tap(find.byTooltip('Unfavorite'));
      await tester.pumpAndSettle();
      expect(feedback, hasLength(enabled ? 1 : 0));
      expect(library.favoriteCalls, hasLength(3));
      expect(tester.takeException(), isNull);
      await disposeScreen(tester);
    });
  }

  testWidgets(
      'mixed favorites adds only missing favorites then unfavorites all',
      (tester) async {
    await mount(tester);
    await select(tester);
    await tester.tap(card('Beta'));
    await tester.pump();
    await tester.tap(find.byTooltip('Favorite'));
    await tester.pumpAndSettle();
    expect(library.favoriteCalls, [items[1].path]);
    expect(container.read(pdfLibraryControllerProvider).favorites,
        containsAll([items[0].path, items[1].path]));
    await tester.tap(find.byTooltip('Unfavorite'));
    await tester.pumpAndSettle();
    expect(container.read(pdfLibraryControllerProvider).favorites, isEmpty);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets(
      'delete cancels safely and partial success retains failures and tabs',
      (tester) async {
    tabs.openTab(items[0]);
    tabs.openTab(items[1]);
    library.failures.add(items[1].path);
    await mount(tester);
    await select(tester);
    await tester.tap(card('Beta'));
    await tester.pump();
    await overflowAction(tester, 'Delete');
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.deleted, isEmpty);
    await overflowAction(tester, 'Delete');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(library.deleted, [items[0].path, items[1].path]);
    expect(tabs.state.tabs.map((tab) => tab.path), [items[1].path]);
    expect(tester.widget<PdfCustomCard>(card('Beta')).selected, isTrue);
    expect(selectedCount(1), findsOneWidget);
    expect(find.textContaining('1 could not be deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets(
      'pending delete disables actions and prevents duplicate submissions',
      (tester) async {
    library.pendingDelete = Completer<bool>();
    await mount(tester);
    await select(tester);
    final dynamic menu = tester
        .widget(find.byWidgetPredicate((widget) => widget is PopupMenuButton));
    final delete = (menu.itemBuilder(
                tester.element(find.byTooltip('More selection actions')))
            as List<PopupMenuEntry>)
        .whereType<PopupMenuItem>()
        .last
        .value;
    menu.onSelected!(delete);
    menu.onSelected!(delete);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(library.deleted, [items[0].path]);
    expect(action(tester, 'Share').onPressed, isNull);
    library.pendingDelete!.complete(true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Exit selection'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets(
      'library changes prune stale selection and combine gets live paths',
      (tester) async {
    await mount(tester);
    await select(tester);
    await overflowAction(tester, 'Select all');
    await tester.pump();
    library.replaceItems(items.sublist(1));
    await tester.pump();
    expect(selectedCount(2), findsOneWidget);
    await tester.tap(find.byTooltip('Merge'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester.widget<MergePdfsPage>(find.byType(MergePdfsPage)).initialFiles,
        items.sublist(1).map((item) => item.path).toList());
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('open overflow resolves deletion against the current library',
      (tester) async {
    await mount(tester);
    await select(tester);
    await tester.tap(card('Beta'));
    await tester.pump();
    await tester.tap(find.byTooltip('More selection actions'));
    await tester.pumpAndSettle();
    library.replaceItems(items.sublist(1));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 PDF?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selectedCount(1), findsOneWidget);
    expect(library.deleted, isEmpty);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('share sends every selected file and a nonempty anchor',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('arcpdf_home_share');
    addTearDown(() => directory.deleteSync(recursive: true));
    final a = File('${directory.path}/Alpha.pdf')..writeAsStringSync('a');
    final b = File('${directory.path}/Beta.pdf')..writeAsStringSync('b');
    library.replaceItems(
        [_item('Alpha', path: a.path), _item('Beta', path: b.path)]);
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await mount(tester);
    await select(tester);
    await overflowAction(tester, 'Select all');
    await tester.pump();
    final share = action(tester, 'Share');
    await tester.runAsync(() async {
      await (share.onPressed! as Future<void> Function())();
    });
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    final arguments = calls.single.arguments as Map;
    expect(arguments['paths'], [a.path, b.path]);
    expect(arguments['originWidth'], greaterThan(0));
    expect(arguments['originHeight'], greaterThan(0));
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('scroll-to-top FAB and last card clear the scaled navbar',
      (tester) async {
    library
        .replaceItems(List.generate(15, (index) => _item('Document $index')));
    await mount(tester, width: 320, scale: 2);
    final scroll = find.descendant(
        of: find.byType(HomeScreen), matching: find.byType(CustomScrollView));
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    // The lazy list refines its estimated extent as the final cards lay out.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final nav = tester.getRect(find.byType(ArcNavBar));
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.bottom, lessThan(nav.top));
    final cards = find
        .byType(PdfCustomCard)
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)));
    final lastBottom =
        cards.map((rect) => rect.bottom).reduce((a, b) => a > b ? a : b);
    expect(lastBottom, lessThanOrEqualTo(fab.top));
    await tester.tap(find.byTooltip('Scroll to top'));
    await tester.pump();
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('missing share files report an error and preserve selection',
      (tester) async {
    await mount(tester);
    await select(tester);
    final share = action(tester, 'Share');
    await tester.runAsync(() async {
      await (share.onPressed! as Future<void> Function())();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not share'), findsOneWidget);
    expect(selectedCount(1), findsOneWidget);
    expect(action(tester, 'Share').onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('favorite failures keep selection available for retry',
      (tester) async {
    library.favoriteFailures.add(items[1].path);
    await mount(tester);
    await select(tester);
    await tester.tap(card('Beta'));
    await tester.pump();
    await tester.tap(find.byTooltip('Favorite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selection kept for retry'), findsOneWidget);
    expect(selectedCount(2), findsOneWidget);
    expect(action(tester, 'Share').onPressed, isNotNull);
    library.favoriteFailures.clear();
    await tester.tap(find.byTooltip('Favorite'));
    await tester.pumpAndSettle();
    expect(container.read(pdfLibraryControllerProvider).favorites,
        containsAll([items[0].path, items[1].path]));
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('keyboard opens overflow and Escape preserves selection',
      (tester) async {
    await mount(tester);
    await select(tester);
    Focus.of(tester.element(find.byIcon(Icons.more_horiz_rounded)))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsNothing);
    expect(selectedCount(1), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Exit selection'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('wide toolbar labels stay on one row and remain height bounded',
      (tester) async {
    await mount(tester, width: 840);
    await select(tester);
    final toolbar =
        tester.getRect(find.byKey(const ValueKey('home-selection-toolbar')));
    expect(toolbar.width, lessThanOrEqualTo(720));
    expect(toolbar.height, lessThanOrEqualTo(56));
    for (final label in ['Share', 'Unfavorite', 'Merge']) {
      expect(find.text(label), findsOneWidget);
      expect(tester.getRect(find.text(label)).center.dy,
          closeTo(toolbar.center.dy, 1));
    }
    final merge =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Merge'));
    expect(merge.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  for (final lowPower in [false, true]) {
    testWidgets(
        'initial empty loading uses static placeholders with low power $lowPower',
        (tester) async {
      lowPowerMode = lowPower;
      library.replaceItems([]);
      library.setLoading(true);
      await mount(tester, disableAnimations: !lowPower);
      expect(
          find.byKey(const ValueKey('home-initial-loading')), findsOneWidget);
      expect(find.byType(Animate), findsNothing);
      expect(find.byType(PdfCardShimmer), findsNothing);
      expect(find.byType(PdfCustomCard), findsNothing);
      expect(find.byType(ArcEmptyState), findsNothing);

      // Indexed results arrive before the full scan completes.
      library.replaceItems(items);
      await tester.pumpAndSettle();
      expect(find.byType(PdfCustomCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey('home-initial-loading')), findsNothing);
      expect(
          find.byKey(const ValueKey('home-library-progress')), findsOneWidget);
      expect(find.byType(ArcEmptyState), findsNothing);
      library.setLoading(false);
      await tester.pumpAndSettle();
      expect(find.byType(PdfCustomCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey('home-library-progress')), findsNothing);
      await disposeScreen(tester);
    });
  }

  testWidgets(
      'routine refresh retains cards and selection with accessible progress',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    await select(tester);
    final beforeCardState = tester.state(card('Alpha'));
    library.setLoading(true);
    await tester.pumpAndSettle();
    expect(find.byType(PdfCustomCard), findsNWidgets(3));
    expect(tester.state(card('Alpha')), same(beforeCardState));
    expect(selectedCount(1), findsOneWidget);
    expect(find.byKey(const ValueKey('home-initial-loading')), findsNothing);
    expect(find.byType(PdfCardShimmer), findsNothing);
    expect(find.byType(ArcEmptyState), findsNothing);
    final progress = find.byKey(const ValueKey('home-library-progress'));
    expect(tester.getSemantics(progress).label, 'Refreshing PDF library');
    expect(tester.widget<Semantics>(progress).properties.liveRegion, isTrue);
    final line = find.descendant(
        of: progress, matching: find.byType(LinearProgressIndicator));
    expect(tester.getSize(line).height, 2);
    expect(tester.widget<LinearProgressIndicator>(line).value, 0.5);
    library.setLoading(false);
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(tester.state(card('Alpha')), same(beforeCardState));
    expect(selectedCount(1), findsOneWidget);
    semantics.dispose();
    await disposeScreen(tester);
  });

  testWidgets(
      'refresh preserves filtered results and defers empty states until completion',
      (tester) async {
    library.setQuery('Beta');
    library.setLoading(true);
    await mount(tester);
    expect(card('Beta'), findsOneWidget);
    expect(card('Alpha'), findsNothing);
    expect(card('Gamma'), findsNothing);
    expect(find.byKey(const ValueKey('home-initial-loading')), findsNothing);
    expect(find.byKey(const ValueKey('home-library-progress')), findsOneWidget);
    library.setQuery('No matching document');
    await tester.pumpAndSettle();
    expect(find.byType(PdfCustomCard), findsNothing);
    expect(find.byType(ArcEmptyState), findsNothing);
    expect(find.byKey(const ValueKey('home-initial-loading')), findsNothing);
    expect(find.byKey(const ValueKey('home-library-progress')), findsOneWidget);
    library.setLoading(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-library-progress')), findsNothing);
    expect(find.text('No results found'), findsOneWidget);
    expect(find.byType(ArcEmptyState), findsOneWidget);
    await disposeScreen(tester);
  });

  testWidgets('refresh progress is indeterminate when motion is enabled',
      (tester) async {
    lowPowerMode = false;
    await mount(tester, disableAnimations: false);
    library.setLoading(true);
    await tester.pump();
    final line = find.descendant(
      of: find.byKey(const ValueKey('home-library-progress')),
      matching: find.byType(LinearProgressIndicator),
    );
    expect(tester.widget<LinearProgressIndicator>(line).value, isNull);
    expect(find.byType(PdfCustomCard), findsNWidgets(3));
    library.setLoading(false);
    await tester.pumpAndSettle();
    expect(line, findsNothing);
    await disposeScreen(tester);
  });

  testWidgets('clearing search cancels its pending debounced query',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Beta');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(pdfLibraryControllerProvider).query, isEmpty);
    expect(find.byType(PdfCustomCard), findsNWidgets(3));
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('filters wrap with 48px targets at large text in $brightness',
        (tester) async {
      await mount(tester, width: 320, scale: 2, brightness: brightness);
      library.replaceTags({
        items.first.path: ['Work', 'Long project reference documents']
      });
      await tester.pumpAndSettle();
      final filters = PdfFilter.values.map((filter) => find.widgetWithText(
          FilterChip,
          switch (filter) {
            PdfFilter.all => 'All',
            PdfFilter.recent => 'Recent',
            PdfFilter.downloads => 'Downloads',
            PdfFilter.large => 'Large Files',
            PdfFilter.folders => 'Folders',
          }));
      final rows = <double>{};
      for (final filter in filters) {
        final rect = tester.getRect(filter);
        expect(rect.shortestSide, greaterThanOrEqualTo(48));
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(304));
        rows.add(rect.top);
      }
      expect(rows.length, greaterThan(1));
      final tag = find.widgetWithText(FilterChip, 'Work');
      expect(tester.getSize(tag).shortestSide, greaterThanOrEqualTo(48));
      final tagSize = tester.getSize(tag);
      await tester.ensureVisible(tag);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(container.read(pdfLibraryControllerProvider).selectedTag, 'Work');
      expect(tester.getSize(tag), tagSize);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(container.read(pdfLibraryControllerProvider).selectedTag, isNull);
      final folders = filters.last;
      await tester.ensureVisible(folders);
      await tester.tap(folders);
      await tester.pumpAndSettle();
      expect(container.read(pdfLibraryControllerProvider).filter,
          PdfFilter.folders);
      expect(tester.takeException(), isNull);
      await disposeScreen(tester);
    });
  }

  testWidgets(
      'resume card updates active document without rebuilding library cards',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tabs.openTab(items[0]);
    tabs.openTab(items[1]);
    await mount(tester, width: 320, scale: 2);
    expect(find.text('Resume reading'), findsOneWidget);
    expect(find.text('2 open tabs'), findsOneWidget);
    expect(
        tester.getSemantics(
            find.bySemanticsLabel('Resume reading Beta.pdf. 2 open tabs')),
        matchesSemantics(
            label: 'Resume reading Beta.pdf. 2 open tabs',
            isButton: true,
            hasTapAction: true));
    final beforeCard = tester.widget<PdfCustomCard>(card('Alpha'));
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Resume reading Alpha.pdf. 2 open tabs'),
        findsOneWidget);
    expect(tester.widget<PdfCustomCard>(card('Alpha')), same(beforeCard));
    await tester.ensureVisible(card('Alpha'));
    await tester.pumpAndSettle();
    await select(tester);
    expect(find.text('Resume reading'), findsNothing);
    await tester.tap(find.byTooltip('Exit selection'));
    await tester.pumpAndSettle();
    expect(tabs.state.activeIndex, 0);
    expect(tabs.state.tabs, items.sublist(0, 2));
    tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Resume reading'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await disposeScreen(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('resume and filters fit 320px at 3x text in $brightness',
        (tester) async {
      final document = _item(
          'Long document title with project notes and reference material');
      tabs.openTab(document);
      final semantics = tester.ensureSemantics();
      await mount(tester, width: 320, scale: 3, brightness: brightness);
      final resume = find.byKey(const ValueKey('home-resume-reading'));
      final rect = tester.getRect(resume);
      expect(rect.left, 16);
      expect(rect.right, 304);
      expect(find.text(document.name), findsOneWidget);
      expect(
          find.bySemanticsLabel('Resume reading ${document.name}. 1 open tab'),
          findsOneWidget);
      for (final chip in find.byType(FilterChip).evaluate()) {
        final chipRect = tester.getRect(find.byWidget(chip.widget));
        expect(chipRect.left, greaterThanOrEqualTo(16));
        expect(chipRect.right, lessThanOrEqualTo(304));
        expect(chipRect.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await disposeScreen(tester);
    });
  }

  testWidgets('resume opens existing reader session without mutating tabs',
      (tester) async {
    tabs.openTab(items.first);
    await mount(tester);
    expect(find.text('1 open tab'), findsOneWidget);
    final before = tabs.state;
    final resume = find.byKey(const ValueKey('home-resume-reading'));
    final navigator = Navigator.of(tester.element(resume));
    expect(tester.getSize(resume).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(resume);
    expect(navigator.canPop(), isTrue);
    expect(tabs.state, same(before));
    // Dispose before building the platform PDF viewer; this test owns only Home.
    await disposeScreen(tester);
  });

  for (final lowPower in [false, true]) {
    testWidgets('selection respects reduced motion with low power $lowPower',
        (tester) async {
      lowPowerMode = lowPower;
      await mount(tester, disableAnimations: !lowPower);
      await select(tester);
      expect(find.byType(Animate), findsNothing);
      await tester.tap(find.byTooltip('More selection actions'));
      await tester.pumpAndSettle();
      expect(find.text('Select all'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeScreen(tester);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('bulk actions fit 320px at 200% text in $brightness',
        (tester) async {
      await mount(tester, scale: 2, width: 320, brightness: brightness);
      await select(tester);
      expect(tester.takeException(), isNull);
      final nav = tester.getRect(find.byType(ArcNavBar));
      final toolbar =
          tester.getRect(find.byKey(const ValueKey('home-selection-toolbar')));
      expect(toolbar.height, lessThanOrEqualTo(56));
      expect(toolbar.width, lessThan(320));
      expect(toolbar.bottom, lessThan(tester.getRect(card('Alpha')).top));
      expect(tester.getRect(card('Alpha')).bottom, lessThan(nav.top));
      for (final label in [
        'Exit selection',
        'Share',
        'Unfavorite',
        'Merge',
        'More selection actions'
      ]) {
        final rect = tester.getRect(find.byTooltip(label));
        expect(rect.size.shortestSide, greaterThanOrEqualTo(44));
        expect(rect.top, greaterThanOrEqualTo(toolbar.top));
        expect(rect.bottom, lessThanOrEqualTo(toolbar.bottom));
      }
      await overflowAction(tester, 'Select all');
      expect(selectedCount(3), findsOneWidget);
      await overflowAction(tester, 'Delete');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selectedCount(3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeScreen(tester);
    });
  }
}
