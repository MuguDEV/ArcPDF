import 'dart:async';

import 'package:arcpdf/src/features/pdf/data/reflow_ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.arcpdf.app/reflow_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) handler;

  setUp(() {
    calls = [];
    handler = (_) async => <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  ReflowOcrService service() =>
      ReflowOcrService(channel: channel, isAndroid: () => true);

  Future<void> nativeProgress(Map<String, Object?> args) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('progress', args)),
      (_) {},
    );
  }

  Map<String, Object?> page(int number, String text) => {
        'page': number,
        'lines': text.isEmpty
            ? <Object?>[]
            : [
                {'text': text}
              ],
      };

  test('returns recognized pages with a request id', () async {
    handler = (_) async => [page(1, 'Hello')];
    final result = await service().recognizePages('/a.pdf', [1]);
    expect(result, isA<OcrOk>());
    expect((result as OcrOk).pages.single['page'], 1);
    expect(calls.single.method, 'recognizePages');
    final args = calls.single.arguments as Map;
    expect(args['requestId'], isA<String>());
    expect(args['pages'], [1]);
  });

  test('request ids are unique per request', () async {
    final s = service();
    await s.recognizePages('/a.pdf', [1]);
    await s.recognizePages('/a.pdf', [1]);
    expect(calls[0].arguments['requestId'],
        isNot(calls[1].arguments['requestId']));
  });

  test('empty recognized text is not a failure', () async {
    handler = (_) async => [page(1, '')];
    expect(await service().recognizePages('/a.pdf', [1]), isA<OcrEmptyText>());
  });

  test('native errors map to typed failures', () async {
    final expected = {
      'ocr_module_missing': OcrFailureKind.moduleMissing,
      'ocr_unsupported_device': OcrFailureKind.unsupportedDevice,
      'ocr_timeout': OcrFailureKind.timeout,
      'ocr_permission_denied': OcrFailureKind.permissionDenied,
      'ocr_cancelled': OcrFailureKind.cancelled,
      'ocr_invalid_request': OcrFailureKind.invalidRequest,
      'ocr_recognition_failed': OcrFailureKind.failed,
      'something_else': OcrFailureKind.failed,
    };
    for (final entry in expected.entries) {
      handler = (_) async => throw PlatformException(
          code: entry.key, details: {'cause': 'IOException'});
      final result = await service().recognizePages('/a.pdf', [1]);
      expect(result, isA<OcrFailure>(), reason: entry.key);
      expect((result as OcrFailure).kind, entry.value, reason: entry.key);
    }
  });

  test('missing plugin is an unsupported device', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final result = await service().recognizePages('/a.pdf', [1]);
    expect((result as OcrFailure).kind, OcrFailureKind.unsupportedDevice);
  });

  test('non Android never calls native', () async {
    final result = await ReflowOcrService(
      channel: channel,
      isAndroid: () => false,
    ).recognizePages('/a.pdf', [1]);
    expect((result as OcrFailure).kind, OcrFailureKind.unsupportedDevice);
    expect(calls, isEmpty);
  });

  test('cancellation before processing never starts native work', () async {
    final token = OcrCancellationToken()..cancel();
    final result =
        await service().recognizePages('/a.pdf', [1], cancellation: token);
    expect((result as OcrFailure).kind, OcrFailureKind.cancelled);
    expect(calls, isEmpty);
  });

  test('cancelling between pages completes at once and tells native', () async {
    final native = Completer<Object?>();
    handler = (call) =>
        call.method == 'recognizePages' ? native.future : Future.value(null);
    final token = OcrCancellationToken();
    final progress = <OcrProgress>[];
    final future = service().recognizePages('/a.pdf', [1, 2, 3],
        cancellation: token, onProgress: progress.add);
    await Future<void>.delayed(Duration.zero);
    final id = calls.first.arguments['requestId'];
    await nativeProgress({'requestId': id, 'page': 1, 'done': 1, 'total': 3});
    expect(progress.single.done, 1);
    token.cancel();
    final result = await future;
    expect((result as OcrFailure).kind, OcrFailureKind.cancelled);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'cancelOcr');
    expect(calls.last.arguments['requestId'], id);
    // A late result from native is not published.
    native.complete([page(1, 'late')]);
    await nativeProgress({'requestId': id, 'page': 2, 'done': 2, 'total': 3});
    expect(progress, hasLength(1));
  });

  test('progress for unknown or finished requests is ignored', () async {
    final progress = <OcrProgress>[];
    final s = service();
    await s.recognizePages('/a.pdf', [1], onProgress: progress.add);
    final id = calls.first.arguments['requestId'];
    await nativeProgress({'requestId': id, 'page': 1, 'done': 1, 'total': 1});
    await nativeProgress(
        {'requestId': 'nope', 'page': 1, 'done': 1, 'total': 1});
    await nativeProgress({'requestId': id});
    expect(progress, isEmpty);
  });

  test('cancelAll calls native', () async {
    await service().cancelAll();
    expect(calls.single.method, 'cancelAll');
  });
}
