import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

/// How the previous process ended, as far as a lightweight marker can tell.
enum PreviousSessionStatus {
  /// No usable marker (first launch after install, cleared data, or the marker
  /// could not be read).
  unknown,

  /// The app left the foreground (paused/hidden/detached) before it stopped.
  clean,

  /// The marker still said "foreground" at next launch: crash, native abort,
  /// out-of-memory kill, force-stop or power loss while the app was in use.
  unclean,
}

class PreviousSessionHealth {
  const PreviousSessionHealth(this.status,
      {this.lastSeenUtc, this.version, this.reason});

  final PreviousSessionStatus status;
  final DateTime? lastSeenUtc;
  final String? version;

  /// Only a short static code such as `no_marker` or `unreadable`.
  final String? reason;

  static const unknown = PreviousSessionHealth(PreviousSessionStatus.unknown);
}

/// Detects abnormal exits with a tiny JSON marker next to the diagnostics
/// archive. It holds no user data: state, timestamps and the app version.
///
/// Call `DiagnosticsSessionMarker.begin()` once, after `AppLogger.init()`. The
/// marker then observes app lifecycle itself: going to the background is a
/// normal way for a session to end, so the state flips to "ended" on
/// hidden/paused/detached and back to "running" on resumed. Everything is
/// best-effort and never throws into the caller.
class DiagnosticsSessionMarker with WidgetsBindingObserver {
  DiagnosticsSessionMarker({
    Future<Directory> Function()? directory,
    Future<String?> Function()? appVersion,
    DateTime Function()? clock,
    bool observeLifecycle = true,
    Future<void> Function(String name, Map<String, Object?> fields)? logEvent,
  })  : _directory = directory ?? _defaultDirectory,
        _appVersion = appVersion ?? _defaultVersion,
        _clock = clock ?? DateTime.now,
        _observeLifecycle = observeLifecycle,
        _logEvent = logEvent ??
            ((name, fields) => AppLogger.event(name, fields: fields));

  static const fileName = 'session.marker.json';
  static const unreadableReason = 'unreadable';
  static const noMarkerReason = 'no_marker';

  /// Process-wide instance used by [begin] and [end].
  static final instance = DiagnosticsSessionMarker();

  /// Starts tracking this session. Safe to call more than once.
  static Future<PreviousSessionHealth> begin() => instance.beginSession();

  /// Marks the session as ended normally (for an explicit, intentional exit).
  static Future<void> end() => instance.endSession();

  final Future<Directory> Function() _directory;
  final Future<String?> Function() _appVersion;
  final DateTime Function() _clock;
  final bool _observeLifecycle;
  final Future<void> Function(String name, Map<String, Object?> fields)
      _logEvent;

  Future<PreviousSessionHealth>? _beginning;
  Future<void> _writes = Future.value();
  PreviousSessionHealth _previous = PreviousSessionHealth.unknown;
  DateTime? _startedUtc;
  String? _version;
  bool _active = false;

  /// Whether [beginSession] has completed in this process.
  bool get isActive => _active;
  PreviousSessionHealth get previousSession => _previous;
  DateTime? get startedUtc => _startedUtc;

  static Future<Directory> _defaultDirectory() async {
    final existing = AppLogger.storageDirectory;
    if (existing != null) return Directory(existing);
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}diagnostics');
  }

  static Future<String?> _defaultVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return null;
    }
  }

  Future<PreviousSessionHealth> beginSession() =>
      _beginning ??= _begin().catchError((Object _) => _previous);

  Future<PreviousSessionHealth> _begin() async {
    File? file;
    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      file = File('${directory.path}${Platform.pathSeparator}$fileName');
    } catch (_) {
      _previous = const PreviousSessionHealth(PreviousSessionStatus.unknown,
          reason: unreadableReason);
    }
    _version = await _safeVersion();
    _startedUtc = _clock().toUtc();
    if (file != null) {
      _file = file;
      _previous = await _readPrevious(file);
    }
    if (_previous.status == PreviousSessionStatus.unclean) {
      await _logEvent('app.previous_session.unclean', {
        'lastSeenUtc': _previous.lastSeenUtc?.toIso8601String(),
        'previousVersion': _previous.version,
        'currentVersion': _version,
      });
    }
    _active = true;
    await _write('running');
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    return _previous;
  }

  File? _file;

  Future<String?> _safeVersion() async {
    try {
      return await _appVersion();
    } catch (_) {
      return null;
    }
  }

  Future<PreviousSessionHealth> _readPrevious(File file) async {
    try {
      if (!await file.exists()) {
        return const PreviousSessionHealth(PreviousSessionStatus.unknown,
            reason: noMarkerReason);
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException();
      final state = decoded['state'];
      final updated = decoded['updatedAt'];
      final version = decoded['version'];
      final status = switch (state) {
        'running' => PreviousSessionStatus.unclean,
        'ended' => PreviousSessionStatus.clean,
        _ => throw const FormatException(),
      };
      return PreviousSessionHealth(
        status,
        lastSeenUtc: updated is String ? DateTime.tryParse(updated) : null,
        version: version is String ? version : null,
      );
    } catch (_) {
      return const PreviousSessionHealth(PreviousSessionStatus.unknown,
          reason: unreadableReason);
    }
  }

  Future<void> endSession() async {
    if (!_active) return;
    await _write('ended');
  }

  /// Resolves once every queued marker write has hit the disk (for tests).
  Future<void> settled() => _writes;

  Future<void> _write(String state) {
    final file = _file;
    if (file == null) return Future.value();
    final now = _clock().toUtc();
    final payload = jsonEncode({
      'v': 1,
      'state': state,
      'startedAt': _startedUtc?.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'version': _version,
    });
    return _writes = _writes.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(payload, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        try {
          await file.writeAsString(payload, flush: true);
        } catch (_) {
          // Diagnostics must never affect the app; the next start reports
          // "unknown" if the marker could not be maintained.
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_write('running'));
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_write('ended'));
      case AppLifecycleState.inactive:
        // Transient (share sheet, permission dialog, app switcher): no change.
        break;
    }
  }

  /// Human/machine readable fields for the diagnostic bundle's session section.
  Map<String, Object?> toReport() => {
        'tracking': _active ? 'active' : 'not_started',
        'previous_session': _previous.status.name,
        'previous_session_last_seen_utc':
            _previous.lastSeenUtc?.toUtc().toIso8601String(),
        'previous_session_version': _previous.version,
        'previous_session_note': _previous.reason,
        'current_session_started_utc': _startedUtc?.toIso8601String(),
      };
}
