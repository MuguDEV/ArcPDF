import 'dart:async';

import 'package:arcpdf/src/features/pdf/data/ocr_module_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> snap(String state,
        {double? progress, String? errorCode, int? bytes, int? total}) =>
    {
      'state': state,
      'progress': progress,
      'errorCode': errorCode,
      'bytesDownloaded': bytes,
      'totalBytes': total,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.arcpdf.app/ocr_module');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late Map<String, Object?> current;
  late Map<String, Map<String, Object?>> onCall;
  late MethodChannelOcrModuleClient client;

  setUp(() {
    calls = [];
    current = snap('notInstalled');
    onCall = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (onCall[call.method] != null) current = onCall[call.method]!;
      return current;
    });
    client = MethodChannelOcrModuleClient(channel: channel, isAndroid: true);
  });
  tearDown(() {
    client.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  OcrModuleController controller({
    bool enabled = true,
    bool background = true,
    OcrModuleClient? withClient,
  }) =>
      OcrModuleController(
        withClient ?? client,
        ocrEnabled: () => enabled,
        backgroundDownloadAllowed: () => background,
        observeLifecycle: false,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> pushNative(Map<String, Object?> value) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('stateChanged', value)),
      (_) {},
    );
  }

  test('already installed module is ready and never downloads', () async {
    current = snap('ready');
    final c = controller();
    await settle();
    await c.requestBackgroundInstallIfAllowed();
    expect(c.state.state, OcrModuleState.ready);
    expect(calls, ['status']);
  });

  test('missing module is reported and background request is deferred only',
      () async {
    final c = controller();
    await settle();
    expect(c.state.state, OcrModuleState.notInstalled);
    onCall['installDeferred'] = snap('waiting');
    await c.requestBackgroundInstallIfAllowed();
    expect(c.state.state, OcrModuleState.waiting);
    expect(calls, contains('installDeferred'));
    expect(calls, isNot(contains('installNow')));
  });

  test('successful install with progress then without progress', () async {
    final c = controller();
    await settle();
    onCall['installNow'] =
        snap('downloading', progress: .25, bytes: 1, total: 4);
    await c.installNow();
    expect(c.state.progress, .25);
    expect(c.state.totalBytes, 4);
    await pushNative(snap('downloading'));
    await settle();
    expect(c.state.state, OcrModuleState.downloading);
    expect(c.state.progress, isNull);
    await pushNative(snap('ready'));
    await settle();
    expect(c.state.isReady, isTrue);
  });

  test('failure then retry; interrupted network surfaces error code', () async {
    final c = controller();
    await settle();
    onCall['installNow'] = snap('failed', errorCode: 'install_failed:7');
    await c.installNow();
    expect(c.state.state, OcrModuleState.failed);
    expect(c.state.errorCode, 'install_failed:7');
    onCall['retry'] = snap('downloading', progress: .1);
    await c.retry();
    expect(c.state.state, OcrModuleState.downloading);
    expect(calls.where((m) => m == 'retry'), hasLength(1));
  });

  test('missing Google Play services is unsupported and never installs',
      () async {
    current = snap('unsupported', errorCode: 'ocr_unsupported_device');
    final c = controller();
    await settle();
    await c.installNow();
    await c.requestBackgroundInstallIfAllowed();
    expect(c.state.state, OcrModuleState.unsupported);
    expect(calls, ['status']);
  });

  test('missing plugin or non Android is unsupported', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    final missing = controller();
    await settle();
    expect(missing.state.state, OcrModuleState.unsupported);
    final other = controller(
      withClient:
          MethodChannelOcrModuleClient(channel: channel, isAndroid: false),
    );
    await settle();
    expect(other.state.state, OcrModuleState.unsupported);
  });

  test('duplicate install requests make one native call', () async {
    final gate = Completer<void>();
    final fake = _GateClient(gate.future);
    final c = controller(withClient: fake);
    await settle();
    final a = c.installNow();
    final b = c.installNow();
    final d = c.requestBackgroundInstallIfAllowed();
    await settle();
    gate.complete();
    await Future.wait([a, b, d]);
    expect(fake.installNowCalls, 1);
    expect(fake.deferredCalls, 0);
    await c.installNow();
    expect(fake.installNowCalls, 1, reason: 'already waiting');
  });

  test('a deferred wait can be replaced by a user download', () async {
    current = {...snap('waiting'), 'deferred': true};
    final c = controller();
    await settle();
    expect(c.state.deferred, isTrue);
    onCall['installNow'] = snap('waiting');
    await c.installNow();
    expect(calls, contains('installNow'));
    expect(c.state.deferred, isFalse);
    calls.clear();
    await c.installNow();
    expect(calls, isEmpty, reason: 'a user wait is not restarted');
  });

  test('restart recovery re-queries native state', () async {
    current = snap('downloading', progress: .5);
    final first = controller();
    await settle();
    first.dispose();
    final second = controller();
    await settle();
    expect(second.state.state, OcrModuleState.downloading);
    expect(second.state.progress, .5);
    expect(calls.where((m) => m == 'status'), hasLength(2));
  });

  test('refresh on resume re-queries native', () async {
    final c = controller();
    await settle();
    current = snap('ready');
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(c.state.isReady, isTrue);
  });

  test('OCR disabled never triggers an install call', () async {
    final c = controller(enabled: false);
    await settle();
    await c.requestBackgroundInstallIfAllowed();
    await c.installNow();
    await c.retry();
    expect(calls, ['status']);
  });

  test('background download preference off never triggers install', () async {
    final c = controller(background: false);
    await settle();
    await c.requestBackgroundInstallIfAllowed();
    expect(calls, ['status']);
  });
}

class _GateClient implements OcrModuleClient {
  _GateClient(this.gate);
  final Future<void> gate;
  int installNowCalls = 0;
  int deferredCalls = 0;
  @override
  Stream<OcrModuleStatus> get updates => const Stream.empty();
  @override
  Future<OcrModuleStatus> status() async =>
      const OcrModuleStatus(OcrModuleState.notInstalled);
  @override
  Future<OcrModuleStatus> check() => status();
  @override
  Future<OcrModuleStatus> installDeferred() async {
    deferredCalls++;
    await gate;
    return const OcrModuleStatus(OcrModuleState.waiting);
  }

  @override
  Future<OcrModuleStatus> installNow() async {
    installNowCalls++;
    await gate;
    return const OcrModuleStatus(OcrModuleState.waiting);
  }

  @override
  Future<OcrModuleStatus> retry() => status();
}
