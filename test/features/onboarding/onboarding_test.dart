import 'package:arcpdf/src/features/onboarding/gesture_illustration.dart';
import 'package:arcpdf/src/features/onboarding/onboarding_controller.dart';
import 'package:arcpdf/src/features/onboarding/onboarding_screen.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _Box extends Mock implements Box<dynamic> {}

/// Settings-style box backed by [store].
Box<dynamic> _storeBox(Map<String, Object?> store) {
  final box = _Box();
  when(() => box.isOpen).thenReturn(true);
  when(() => box.isNotEmpty).thenAnswer((_) => store.isNotEmpty);
  when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((call) =>
          store[call.positionalArguments.first as String] ??
          call.namedArguments[#defaultValue]);
  when(() => box.put(any(), any())).thenAnswer((call) async {
    store[call.positionalArguments.first as String] =
        call.positionalArguments[1];
  });
  return box;
}

Box<dynamic> _historyBox({required bool hasData}) {
  final box = _Box();
  when(() => box.isOpen).thenReturn(true);
  when(() => box.isNotEmpty).thenReturn(hasData);
  return box;
}

class _Library extends StateNotifier<PdfLibraryState>
    implements PdfLibraryController {
  _Library(this.result) : super(const PdfLibraryState());

  final StoragePermissionStatus result;
  final requests = <bool>[];

  @override
  Future<void> refresh({bool requestPermission = false}) async {
    requests.add(requestPermission);
    if (requestPermission) {
      state = state.copyWith(permissionStatus: result);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.container, this.library, this.store);
  final ProviderContainer container;
  final _Library library;
  final Map<String, Object?> store;

  bool get completed => container.read(onboardingCompletedProvider);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool lowPower = true,
  bool disableAnimations = false,
  double textScale = 1,
  Size size = const Size(320, 640),
  StoragePermissionStatus permission = StoragePermissionStatus.granted,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settingsBox = _Box();
  when(() => settingsBox.get(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((call) => switch (call.positionalArguments.first) {
            'lowPowerMode' => lowPower,
            'useHaptics' => false,
            _ => call.namedArguments[#defaultValue],
          });
  final store = <String, Object?>{};
  final library = _Library(permission);
  final container = ProviderContainer(overrides: [
    settingsControllerProvider
        .overrideWith((ref) => SettingsController(settingsBox)),
    onboardingCompletedProvider
        .overrideWith((ref) => OnboardingCompletedNotifier(_storeBox(store))),
    pdfLibraryControllerProvider.overrideWith((ref) => library),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: const OnboardingScreen(),
    ),
  ));
  await tester.pump();
  return _Harness(container, library, store);
}

bool _value(OnboardingCompletedNotifier notifier) {
  late bool value;
  notifier.addListener((state) => value = state)();
  return value;
}

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  // Long enough for page motion and the button's ink effect to finish.
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  group('OnboardingCompletedNotifier', () {
    test('is completed when no box is available', () {
      final notifier = OnboardingCompletedNotifier(null);
      expect(_value(notifier), isTrue);
    });

    test('is pending for a fresh install and persists on complete()', () async {
      final store = <String, Object?>{};
      final notifier = OnboardingCompletedNotifier(_storeBox(store),
          historyBoxes: [_historyBox(hasData: false), null]);
      expect(_value(notifier), isFalse);
      await notifier.complete();
      expect(_value(notifier), isTrue);
      expect(store[onboardingCompletedKey], isTrue);
    });

    test('honours the persisted flag', () {
      final notifier = OnboardingCompletedNotifier(
          _storeBox({onboardingCompletedKey: true}));
      expect(_value(notifier), isTrue);
    });

    test('existing users with library history skip and are remembered',
        () async {
      final store = <String, Object?>{};
      final notifier =
          OnboardingCompletedNotifier(_storeBox(store), historyBoxes: [
        _historyBox(hasData: false),
        _historyBox(hasData: true),
      ]);
      expect(_value(notifier), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(store[onboardingCompletedKey], isTrue);
    });

    test('unreadable boxes never trap the user', () {
      final broken = _Box();
      when(() => broken.get(any(), defaultValue: any(named: 'defaultValue')))
          .thenThrow(StateError('closed'));
      expect(_value(OnboardingCompletedNotifier(broken)), isTrue);

      final badHistory = _Box();
      when(() => badHistory.isOpen).thenThrow(StateError('closed'));
      expect(hasLibraryHistory([badHistory]), isFalse);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('three cards via Next, no overflow at 320px and 3x text',
        (tester) async {
      final h = await _pump(tester, textScale: 3);
      final semantics = tester.ensureSemantics();
      expect(find.text('Let ArcPDF find your PDFs'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);

      await _tapText(tester, 'Next');
      expect(find.text('Keep files in a private vault'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
      expect(find.textContaining('Set up later in Settings'), findsOneWidget);

      await _tapText(tester, 'Next');
      expect(find.text('Read with your hands'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 3 of 3'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Fling to travel'), findsOneWidget);

      expect(h.completed, isFalse);
      await _tapText(tester, 'Get started');
      expect(h.completed, isTrue);
      expect(h.store[onboardingCompletedKey], isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('primary targets are at least 48dp', (tester) async {
      await _pump(tester);
      for (final label in ['Skip', 'Allow access', 'Not now', 'Next']) {
        final button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
        final size = tester.getSize(button.first);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('Not now advances without requesting permission',
        (tester) async {
      final h = await _pump(tester);
      await _tapText(tester, 'Not now');
      expect(find.text('Keep files in a private vault'), findsOneWidget);
      expect(h.library.requests, isEmpty);
    });

    testWidgets('Allow access reuses the library permission flow',
        (tester) async {
      final h = await _pump(tester);
      await _tapText(tester, 'Allow access');
      expect(h.library.requests, [true]);
      expect(find.textContaining('Access allowed'), findsWidgets);
      // Granted: the request button is done and Not now is gone.
      expect(find.text('Not now'), findsNothing);
    });

    testWidgets('denied permission offers a retry and a way forward',
        (tester) async {
      final h = await _pump(tester, permission: StoragePermissionStatus.denied);
      await _tapText(tester, 'Allow access');
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await _tapText(tester, 'Try again');
      expect(h.library.requests, [true, true]);
      await _tapText(tester, 'Next');
      expect(find.text('Keep files in a private vault'), findsOneWidget);
    });

    testWidgets('Skip completes from the first card', (tester) async {
      final h = await _pump(tester);
      await _tapText(tester, 'Skip');
      expect(h.completed, isTrue);
      expect(h.store[onboardingCompletedKey], isTrue);
      expect(h.library.requests, isEmpty);
    });

    testWidgets('arrow keys and Back navigate', (tester) async {
      await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Keep files in a private vault'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Let ArcPDF find your PDFs'), findsOneWidget);
      // Cannot move past the ends.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Let ArcPDF find your PDFs'), findsOneWidget);

      await _tapText(tester, 'Next');
      await _tapBack(tester);
      expect(find.text('Let ArcPDF find your PDFs'), findsOneWidget);
    });

    testWidgets('swiping moves between cards', (tester) async {
      await _pump(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Keep files in a private vault'), findsOneWidget);
    });

    testWidgets('low power mode runs no animations', (tester) async {
      await _pump(tester);
      await _tapText(tester, 'Next');
      await _tapText(tester, 'Next');
      expect(find.byType(GestureIllustration), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disableAnimations runs no animations', (tester) async {
      await _pump(tester, lowPower: false, disableAnimations: true);
      await _tapText(tester, 'Next');
      await _tapText(tester, 'Next');
      expect(tester.binding.transientCallbackCount, 0);
      await _tapText(tester, 'Get started');
      expect(tester.takeException(), isNull);
    });

    testWidgets('illustration animates only while its card is current',
        (tester) async {
      final h = await _pump(tester, lowPower: false);
      expect(tester.binding.transientCallbackCount, 0);
      await _tapText(tester, 'Next');
      expect(tester.binding.transientCallbackCount, 0);
      await _tapText(tester, 'Next');
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      // Paint a few frames across scene boundaries.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await _tapBack(tester);
      expect(tester.binding.transientCallbackCount, 0);
      await _tapText(tester, 'Next');
      await _tapText(tester, 'Get started');
      expect(h.completed, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
