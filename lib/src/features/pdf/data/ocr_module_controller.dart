import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../settings/settings_controller.dart';

/// Install state of the downloadable OCR module. The native side (Google Play
/// services) is the source of truth; this only mirrors it.
enum OcrModuleState {
  checking,
  notInstalled,
  waiting,
  downloading,
  ready,
  failed,
  unsupported,
}

@immutable
class OcrModuleStatus {
  const OcrModuleStatus(
    this.state, {
    this.progress,
    this.errorCode,
    this.bytesDownloaded,
    this.totalBytes,
    this.deferred = false,
  });

  static const checking = OcrModuleStatus(OcrModuleState.checking);
  static const unsupported = OcrModuleStatus(OcrModuleState.unsupported);

  final OcrModuleState state;

  /// 0..1, or null when Play services reports no progress.
  final double? progress;
  final String? errorCode;
  final int? bytesDownloaded;
  final int? totalBytes;

  /// True while [OcrModuleState.waiting] comes from a deferred request that
  /// Play services schedules itself. The user may still start a download now.
  final bool deferred;

  bool get isReady => state == OcrModuleState.ready;

  factory OcrModuleStatus.fromMap(Object? raw) {
    if (raw is! Map) return OcrModuleStatus.unsupported;
    final name = raw['state'];
    final state =
        OcrModuleState.values.where((value) => value.name == name).firstOrNull;
    if (state == null) return OcrModuleStatus.unsupported;
    final progress = raw['progress'];
    final bytes = raw['bytesDownloaded'];
    final total = raw['totalBytes'];
    final error = raw['errorCode'];
    return OcrModuleStatus(
      state,
      progress: progress is num && progress.isFinite
          ? progress.toDouble().clamp(0.0, 1.0)
          : null,
      errorCode: error is String ? error : null,
      bytesDownloaded: bytes is int ? bytes : null,
      totalBytes: total is int ? total : null,
      deferred: raw['deferred'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OcrModuleStatus &&
      other.state == state &&
      other.progress == progress &&
      other.errorCode == errorCode &&
      other.bytesDownloaded == bytesDownloaded &&
      other.totalBytes == totalBytes &&
      other.deferred == deferred;

  @override
  int get hashCode =>
      Object.hash(
        state,
        progress,
        errorCode,
        bytesDownloaded,
        totalBytes,
        deferred,
      );

  @override
  String toString() => 'OcrModuleStatus(${state.name}, progress: $progress, '
      'error: $errorCode)';
}

/// Platform access for the OCR module. Replace in tests.
abstract class OcrModuleClient {
  Future<OcrModuleStatus> status();
  Future<OcrModuleStatus> check();
  Future<OcrModuleStatus> installDeferred();
  Future<OcrModuleStatus> installNow();
  Future<OcrModuleStatus> retry();

  /// Native-initiated state changes.
  Stream<OcrModuleStatus> get updates;
}

class MethodChannelOcrModuleClient implements OcrModuleClient {
  MethodChannelOcrModuleClient({MethodChannel? channel, bool? isAndroid})
      : _channel = channel ?? const MethodChannel('com.arcpdf.app/ocr_module'),
        _android = isAndroid ?? Platform.isAndroid {
    if (_android) _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final bool _android;
  final _updates = StreamController<OcrModuleStatus>.broadcast();

  @override
  Stream<OcrModuleStatus> get updates => _updates.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'stateChanged' && !_updates.isClosed) {
      _updates.add(OcrModuleStatus.fromMap(call.arguments));
    }
  }

  Future<OcrModuleStatus> _invoke(String method) async {
    if (!_android) return OcrModuleStatus.unsupported;
    try {
      return OcrModuleStatus.fromMap(
        await _channel.invokeMethod<Object?>(method),
      );
    } on MissingPluginException {
      return OcrModuleStatus.unsupported;
    } on PlatformException catch (error) {
      return OcrModuleStatus(OcrModuleState.failed, errorCode: error.code);
    }
  }

  @override
  Future<OcrModuleStatus> status() => _invoke('status');
  @override
  Future<OcrModuleStatus> check() => _invoke('check');
  @override
  Future<OcrModuleStatus> installDeferred() => _invoke('installDeferred');
  @override
  Future<OcrModuleStatus> installNow() => _invoke('installNow');
  @override
  Future<OcrModuleStatus> retry() => _invoke('retry');

  void dispose() {
    if (_android) _channel.setMethodCallHandler(null);
    _updates.close();
  }
}

/// Mirrors the native OCR module state. It never starts a download unless OCR
/// is enabled, and background requests use deferred install only.
class OcrModuleController extends StateNotifier<OcrModuleStatus>
    with WidgetsBindingObserver {
  OcrModuleController(
    this._client, {
    bool Function()? ocrEnabled,
    bool Function()? backgroundDownloadAllowed,
    bool observeLifecycle = true,
  })  : _ocrEnabled = ocrEnabled ?? (() => true),
        _backgroundAllowed = backgroundDownloadAllowed ?? (() => true),
        _observing = observeLifecycle,
        super(OcrModuleStatus.checking) {
    _subscription = _client.updates.listen(_apply);
    if (_observing) WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  final OcrModuleClient _client;
  final bool Function() _ocrEnabled;
  final bool Function() _backgroundAllowed;
  final bool _observing;
  StreamSubscription<OcrModuleStatus>? _subscription;
  Future<void>? _installing;

  void _apply(OcrModuleStatus next) {
    if (mounted) state = next;
  }

  /// Re-queries native state, for example on start or after resume.
  Future<void> refresh() async {
    try {
      _apply(await _client.status());
    } catch (error) {
      unawaited(AppLogger.warning('OCR module status failed: $error'));
    }
  }

  /// Asks Play services to download now. The user chose this action.
  Future<void> installNow() => _install(() => _client.installNow());

  /// Retries a failed install.
  Future<void> retry() => _install(() => _client.retry());

  /// Queues a deferred install when OCR and background download are enabled.
  /// Duplicate calls and already installed or running states are no-ops.
  Future<void> requestBackgroundInstallIfAllowed() async {
    if (!_ocrEnabled() || !_backgroundAllowed()) return;
    if (state.state == OcrModuleState.checking) await refresh();
    if (!mounted || state.state != OcrModuleState.notInstalled) return;
    await _install(() => _client.installDeferred());
  }

  Future<void> _install(Future<OcrModuleStatus> Function() request) {
    if (!_ocrEnabled()) return Future.value();
    final running = _installing;
    if (running != null) return running;
    switch (state.state) {
      case OcrModuleState.ready ||
            OcrModuleState.unsupported ||
            OcrModuleState.downloading:
        return Future.value();
      // A deferred wait is Play services' own schedule; the user may override it.
      case OcrModuleState.waiting when !state.deferred:
        return Future.value();
      default:
    }
    final future = () async {
      try {
        _apply(await request());
      } catch (error) {
        unawaited(AppLogger.warning('OCR module install failed: $error'));
      } finally {
        _installing = null;
      }
    }();
    return _installing = future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}

final ocrModuleClientProvider = Provider<OcrModuleClient>((ref) {
  final client = MethodChannelOcrModuleClient();
  ref.onDispose(client.dispose);
  return client;
});

final ocrModuleControllerProvider =
    StateNotifierProvider<OcrModuleController, OcrModuleStatus>((ref) {
  return OcrModuleController(
    ref.watch(ocrModuleClientProvider),
    ocrEnabled: () => ref.read(settingsControllerProvider).enableOcr,
    backgroundDownloadAllowed: () =>
        ref.read(settingsControllerProvider).ocrBackgroundDownload,
  );
});
