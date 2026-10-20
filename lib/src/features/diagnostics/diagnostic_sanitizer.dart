/// Defence-in-depth scrubbing for everything that ends up in a bug report.
///
/// `AppLogger` already redacts what it records; this runs again over logs and
/// over every value that a section source supplies, so a future regression in
/// one layer cannot leak a path, secret or document name into a shared file.
/// All methods are pure and idempotent: `text(text(x)) == text(x)`.
abstract final class DiagnosticSanitizer {
  static final _singleLineControl = RegExp(r'[\x00-\x1F\x7F]');
  static final _multiLineControl = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
  static final _carriageReturn = RegExp(r'\r');

  // Quantifiers are bounded so adversarial 4 KB runs stay linear-ish.
  static final _uri =
      RegExp(r'''\b[A-Za-z][A-Za-z0-9+.\-]{0,31}://[^\s)\]'"]+''');
  static final _windowsPath = RegExp(r'\b[A-Za-z]:[\\/][^\r\n\t]*');
  static final _uncPath = RegExp(r'\\\\[^\s\\]+\\[^\r\n\t]*');
  static final _knownRootPath = RegExp(
      r'(?<![\w.:/])/(?:storage|sdcard|data|home|Users|private|tmp|var|mnt|proc|system|vendor|Volumes|opt|root)\b[^\r\n\t]*');
  static final _multiSegmentPath =
      RegExp(r'''(?<![\w.:/])/[^\s/()\[\]'"]+(?:/[^\s/()\[\]'"]+)+/?''');
  static final _documentName = RegExp(
      r'''(?<![^\s/\\:=,;"'<>|])(?:[^\s/\\:=,;"'<>|]+ +){0,5}[^\s/\\:=,;"'<>|]+\.(?:pdf|docx?|xlsx?|pptx?|epub|jpe?g|png)\b''',
      caseSensitive: false);
  static final _email = RegExp(
      r'\b[A-Z0-9._%+-]{1,64}@[A-Z0-9.-]{1,255}\.[A-Z]{2,24}\b',
      caseSensitive: false);
  static final _bearer = RegExp(r'\bBearer\s+\S+', caseSensitive: false);
  static final _secretAssignment = RegExp(
      r'''\b(password|passwd|passphrase|passcode|pin|pattern|otp|token|secret|salt|authorization|api[_-]?key|(?:encryption|private|vault|master|secret)[_-]?key)\b["']?\s*[:=]\s*["']?(?:\[[A-Za-z-]+\]|[^\s"',;}\]]+)''',
      caseSensitive: false);
  static final _spokenPin =
      RegExp(r'\b(pin|passcode)\s+\d{4,8}\b', caseSensitive: false);
  static final _opaqueToken = RegExp(r'\b[A-Za-z0-9_\-+/=]{32,}\b');
  static final _digit = RegExp(r'\d');

  static final _camelBoundary = RegExp(r'([a-z0-9])([A-Z])');
  static final _keySeparators = RegExp(r'[^a-z0-9]+');
  static final _edgeUnderscores = RegExp(r'^_+|_+$');
  static final _longSensitiveKey = RegExp(
      r'serial|advertis|account|passw|passcode|secret|token|credential|imei|android_?id|device_?id|computer_?name|user_?name|owner|path|director|email|fingerprint|bootloader|ssid|api_?key');
  static final _shortSensitiveKey =
      RegExp(r'(^|_)(pin|pattern|mac|uuid|udid|salt)(_|$)');

  /// Scrubs [input] and bounds it to [limit] UTF-16 units. Single-line by
  /// default (so values cannot forge additional report lines); stack traces
  /// pass `multiline: true` to keep their frame breaks.
  static String text(String input, {int limit = 512, bool multiline = false}) {
    var safe = input.length > limit ? '${input.substring(0, limit)}…' : input;
    if (multiline) {
      safe = safe
          .replaceAll(_carriageReturn, '')
          .replaceAll(_multiLineControl, ' ');
    } else {
      safe = safe.replaceAll(_singleLineControl, ' ');
    }
    safe = safe.replaceAll(_uri, '[uri]');
    safe = safe.replaceAll(_windowsPath, '[path]');
    safe = safe.replaceAll(_uncPath, '[path]');
    safe = safe.replaceAll(_knownRootPath, '[path]');
    safe = safe.replaceAll(_multiSegmentPath, '[path]');
    safe = safe.replaceAll(_documentName, '[document]');
    safe = safe.replaceAll(_email, '[email]');
    safe = safe.replaceAll(_bearer, 'Bearer [redacted]');
    safe = safe.replaceAllMapped(
        _secretAssignment, (match) => '${match[1]}=[redacted]');
    safe =
        safe.replaceAllMapped(_spokenPin, (match) => '${match[1]} [redacted]');
    // Only long runs containing a digit look like keys/hashes; long plain
    // words (class names) are kept.
    safe = safe.replaceAllMapped(_opaqueToken,
        (match) => _digit.hasMatch(match[0]!) ? '[token]' : match[0]!);
    return safe;
  }

  /// Report keys are machine-parseable identifiers: `[a-z0-9_]+`.
  static String key(String input) {
    final safe = input
        .replaceAllMapped(_camelBoundary, (match) => '${match[1]}_${match[2]}')
        .toLowerCase()
        .replaceAll(_keySeparators, '_')
        .replaceAll(_edgeUnderscores, '');
    if (safe.isEmpty) return 'unnamed';
    return safe.length > 64 ? safe.substring(0, 64) : safe;
  }

  /// Keys that must never carry a value, whatever a source supplies.
  static bool isSensitiveKey(String normalizedKey) =>
      _longSensitiveKey.hasMatch(normalizedKey) ||
      _shortSensitiveKey.hasMatch(normalizedKey);

  /// Renders a scalar (or short list of scalars) as one safe line of text.
  /// Arbitrary objects are never stringified: their `toString` may hold data.
  static String value(Object? value, {int limit = 256}) {
    String scalar(Object? item) {
      if (item == null) return 'null';
      if (item is bool) return '$item';
      if (item is int) return '$item';
      if (item is double) return item.isFinite ? '$item' : 'n/a';
      if (item is Enum) return text(item.name, limit: limit);
      if (item is String) return text(item, limit: limit);
      return '<${item.runtimeType}>';
    }

    if (value is Iterable) {
      return value.take(32).map(scalar).join(',');
    }
    return scalar(value);
  }
}
