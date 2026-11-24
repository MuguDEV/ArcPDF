import 'package:arcpdf/src/features/pdf/data/ocr_module_controller.dart';
import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockBox extends Mock implements Box {}

class FakeClient implements OcrModuleClient {
  FakeClient(this.initial);
  OcrModuleStatus initial;
  final calls = <String>[];
  @override
  Stream<OcrModuleStatus> get updates => const Stream.empty();
  @override
  Future<OcrModuleStatus> status() async => initial;
  @override
  Future<OcrModuleStatus> check() async => initial;
  @override
  Future<OcrModuleStatus> installDeferred() async {
    calls.add('installDeferred');
    return initial;
  }

  @override
  Future<OcrModuleStatus> installNow() async {
    calls.add('installNow');
    return const OcrModuleStatus(OcrModuleState.downloading);
  }

  @override
  Future<OcrModuleStatus> retry() async {
    calls.add('retry');
    return const OcrModuleStatus(OcrModuleState.downloading, progress: .4);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockBox box;
  late Map<String, Object?> stored;

  setUp(() {
    box = MockBox();
    stored = {};
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) =>
            stored[call.positionalArguments.first] ??
            call.namedArguments[#defaultValue]);
    when(() => box.get(any())).thenReturn(null);
    when(() => box.put(any(), any())).thenAnswer((call) async {
      stored[call.positionalArguments[0] as String] =
          call.positionalArguments[1];
    });
    PackageInfo.setMockInitialValues(
      appName: 'ArcPDF',
      packageName: 'com.arcpdf',
      version: '1.4.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('OCR flags default on and persist', () async {
    final controller = SettingsController(box);
    expect(controller.state.enableOcr, isTrue);
    expect(controller.state.ocrBackgroundDownload, isTrue);
    await controller.setEnableOcr(false);
    await controller.setOcrBackgroundDownload(false);
    expect(stored['enableOcr'], false);
    expect(stored['ocrBackgroundDownload'], false);
    final reloaded = SettingsController(box);
    expect(reloaded.state.enableOcr, isFalse);
    expect(reloaded.state.ocrBackgroundDownload, isFalse);
  });

  Future<FakeClient> mount(
    WidgetTester tester,
    OcrModuleStatus status,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FakeClient(status);
    final settings = SettingsController(box);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith((ref) => settings),
        securityControllerProvider
            .overrideWith((ref) => SecurityController(box)),
        ocrModuleControllerProvider.overrideWith((ref) => OcrModuleController(
              client,
              ocrEnabled: () => settings.state.enableOcr,
              observeLifecycle: false,
            )),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.text('Text recognition'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    return client;
  }

  testWidgets('not installed shows Download now and calls installNow',
      (tester) async {
    final client =
        await mount(tester, const OcrModuleStatus(OcrModuleState.notInstalled));
    expect(find.textContaining('Not downloaded'), findsOneWidget);
    await tester.ensureVisible(find.text('Download now'));
    await tester.tap(find.text('Download now'));
    await tester.pump();
    expect(client.calls, ['installNow']);
    expect(find.text('Enable OCR for scanned PDFs'), findsOneWidget);
    expect(find.textContaining('nothing is uploaded'), findsNothing,
        reason: 'privacy text says never uploaded');
    expect(find.textContaining('never uploaded'), findsOneWidget);
  });

  testWidgets('deferred wait offers Download now, a user wait does not',
      (tester) async {
    final client = await mount(
      tester,
      const OcrModuleStatus(OcrModuleState.waiting, deferred: true),
    );
    await tester.ensureVisible(find.text('Download now'));
    await tester.tap(find.text('Download now'));
    await tester.pump();
    expect(client.calls, ['installNow']);
  });

  testWidgets('user wait has no download button', (tester) async {
    await mount(tester, const OcrModuleStatus(OcrModuleState.waiting));
    expect(find.text('Download now'), findsNothing);
  });

  testWidgets('failed shows Retry and calls retry', (tester) async {
    final client = await mount(
      tester,
      const OcrModuleStatus(OcrModuleState.failed, errorCode: 'install_failed'),
    );
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(client.calls, ['retry']);
  });

  testWidgets('ready shows status without actions', (tester) async {
    await mount(tester, const OcrModuleStatus(OcrModuleState.ready));
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.text('Download now'), findsNothing);
  });

  testWidgets('unsupported explains PDF features keep working', (tester) async {
    await mount(tester, OcrModuleStatus.unsupported);
    expect(find.textContaining('Not available on this device'), findsOneWidget);
    expect(find.text('Download now'), findsNothing);
  });

  testWidgets('reported progress is determinate', (tester) async {
    await mount(tester,
        const OcrModuleStatus(OcrModuleState.downloading, progress: .5));
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, .5);
  });

  testWidgets('missing progress is indeterminate', (tester) async {
    await mount(tester, const OcrModuleStatus(OcrModuleState.downloading));
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, isNull);
  });

  testWidgets('OCR switch disables downloading', (tester) async {
    final client =
        await mount(tester, const OcrModuleStatus(OcrModuleState.notInstalled));
    await tester.tap(find.text('Enable OCR for scanned PDFs'));
    await tester.pumpAndSettle();
    expect(stored['enableOcr'], false);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Download now'));
    expect(button.onPressed, isNull);
    expect(client.calls, isEmpty);
  });
}
