import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/navigation/navigation_controller.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/sharing/intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class TestReceiver extends ReceiveSharingIntent {
  final events = StreamController<List<SharedMediaFile>>.broadcast();
  List<SharedMediaFile> initial = [];
  bool failInitial = false;
  bool failReset = false;
  int streamCalls = 0;
  int resets = 0;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() {
    streamCalls++;
    return events.stream;
  }

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async {
    if (failInitial) throw StateError('Initial intent failed');
    return initial;
  }

  @override
  Future<void> reset() async {
    resets++;
    if (failReset) throw StateError('Reset failed');
  }
}

class MockBox<T> extends Mock implements Box<T> {}

class MockScanner extends Mock implements PdfScannerService {}

MockBox<String> emptyStringBox() {
  final box = MockBox<String>();
  when(() => box.keys).thenReturn([]);
  when(() => box.values).thenReturn([]);
  return box;
}

class RecordingLibrary extends PdfLibraryController {
  RecordingLibrary(super.scanner, super.favorites, super.recents,
      super.timestamps, super.tags);
  final opened = <PdfFileItem>[];
  bool failHistory = false;

  @override
  Future<void> markRecent(PdfFileItem item) async {
    if (failHistory) throw StateError('History failed');
    opened.add(item);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestReceiver receiver;
  late ReceiveSharingIntent previousReceiver;
  late RecordingLibrary library;
  late ProviderContainer container;
  late IntentService service;
  final navigated = <PdfFileItem>[];

  SharedMediaFile shared(String path,
          {String? mimeType, SharedMediaType type = SharedMediaType.file}) =>
      SharedMediaFile(path: path, type: type, mimeType: mimeType);

  File writePdf(String name, {String content = '%PDF-1.7\nbody'}) {
    final file = File(p.join(directory.path, name));
    file.writeAsStringSync(content);
    return file;
  }

  Future<void> waitForIntent(WidgetTester tester) async {
    // Alternate real I/O completion with fake-zone continuation/timer work.
    for (var tick = 0; tick < 12; tick++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, {bool finishSplash = true}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: service.navigatorKey,
      home: const Scaffold(body: Text('Home')),
    ));
    if (finishSplash) service.splashCompleter.complete();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_intent_');
    previousReceiver = ReceiveSharingIntent.instance;
    receiver = TestReceiver();
    ReceiveSharingIntent.instance = receiver;
    final timestamps = MockBox<int>();
    when(() => timestamps.toMap()).thenReturn({});
    final tags = MockBox<List<String>>();
    when(() => tags.keys).thenReturn([]);
    final scanner = MockScanner();
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) async => const ScanResult(
            files: [], permissionStatus: StoragePermissionStatus.granted));
    library = RecordingLibrary(
        scanner, emptyStringBox(), emptyStringBox(), timestamps, tags);
    navigated.clear();
    container = ProviderContainer(overrides: [
      pdfLibraryControllerProvider.overrideWith((ref) => library),
    ]);
    final testService = Provider<IntentService>((ref) {
      final instance = IntentService(ref, viewerBuilder: (item) {
        navigated.add(item);
        return Scaffold(body: Text('Opened ${item.name}'));
      });
      ref.onDispose(instance.dispose);
      return instance;
    });
    service = container.read(testService);
  });

  tearDown(() async {
    service.dispose();
    container.dispose();
    if (library.mounted) library.dispose();
    await receiver.events.close();
    ReceiveSharingIntent.instance = previousReceiver;
    await directory.delete(recursive: true);
  });

  testWidgets(
      'opens a cold-start PDF through the root Navigator and records history',
      (tester) async {
    final file = writePdf('initial.pdf');
    receiver.initial = [shared(file.path)];
    await mount(tester);
    service.init();
    service.init();
    await waitForIntent(tester);
    expect(find.text('Opened initial.pdf'), findsOneWidget);
    expect(library.opened.single.path, file.path);
    expect(receiver.streamCalls, 1);
    expect(receiver.resets, 1);
    expect(navigated, isNotEmpty);
  });

  testWidgets(
      'waits for splash and coalesces duplicate initial and live intents',
      (tester) async {
    final file = writePdf('wait.pdf');
    receiver.initial = [shared(file.path)];
    await mount(tester, finishSplash: false);
    service.init();
    receiver.events.add([shared(file.path)]);
    await waitForIntent(tester);
    expect(find.text('Opened wait.pdf'), findsNothing);
    service.splashCompleter.complete();
    await waitForIntent(tester);
    expect(find.text('Opened wait.pdf'), findsOneWidget);
    expect(library.opened, hasLength(1));
  });

  testWidgets(
      'skips invalid candidates and accepts file URIs and PDF MIME type',
      (tester) async {
    final file = writePdf('mime-only');
    final corrupt = writePdf('corrupt.pdf', content: 'not a PDF');
    await mount(tester);
    service.init();
    receiver.events.add([
      shared('https://example.com/fake.pdf', type: SharedMediaType.url),
      shared('content://provider/document.pdf'),
      shared('relative.pdf'),
      shared(p.join(directory.path, 'missing.pdf')),
      shared(corrupt.path),
      shared(file.uri.toString(), mimeType: 'application/pdf'),
    ]);
    await waitForIntent(tester);
    expect(library.opened.single.path, file.path);
    expect(find.text('Opened mime-only'), findsOneWidget);
  });

  testWidgets('opens only the first valid PDF in a batch', (tester) async {
    final first = writePdf('first.pdf');
    final second = writePdf('second.pdf');
    await mount(tester);
    service.init();
    receiver.events.add([shared(first.path), shared(second.path)]);
    await waitForIntent(tester);
    expect(library.opened.map((item) => item.path), [first.path]);
    expect(find.text('Opened first.pdf'), findsOneWidget);
    expect(find.text('Opened second.pdf'), findsNothing);
  });

  testWidgets('initial and stream errors do not break later incoming files',
      (tester) async {
    final file = writePdf('after-error.pdf');
    receiver.failInitial = true;
    await mount(tester);
    service.init();
    await waitForIntent(tester);
    receiver.events.addError(StateError('Stream error'));
    receiver.events.add([shared(file.path)]);
    await waitForIntent(tester);
    expect(find.text('Opened after-error.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset or history errors do not prevent navigation',
      (tester) async {
    final file = writePdf('open-anyway.pdf');
    receiver.initial = [shared(file.path)];
    receiver.failReset = true;
    library.failHistory = true;
    await mount(tester);
    service.init();
    await waitForIntent(tester);
    expect(find.text('Opened open-anyway.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels queued work and unsubscribes idempotently',
      (tester) async {
    final file = writePdf('cancel.pdf');
    await mount(tester, finishSplash: false);
    service.init();
    receiver.events.add([shared(file.path)]);
    await waitForIntent(tester);
    service.dispose();
    service.dispose();
    service.init();
    await waitForIntent(tester);
    expect(receiver.events.hasListener, isFalse);
    expect(library.opened, isEmpty);
    expect(find.text('Opened cancel.pdf'), findsNothing);
    expect(receiver.streamCalls, 1);
  });

  test('production provider observes splash and disposes its subscription',
      () async {
    final production = container.read(intentServiceProvider);
    production.init();
    expect(production.splashCompleter.isCompleted, isFalse);
    container.read(splashDoneProvider.notifier).state = true;
    expect(production.splashCompleter.isCompleted, isTrue);
    container.dispose();
    expect(receiver.events.hasListener, isFalse);
    // Avoid disposing this container twice in tearDown.
    container = ProviderContainer();
  });
}
