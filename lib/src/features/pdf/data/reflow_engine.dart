import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../../core/native/native_job_runtime.dart';
import '../domain/reflow_document.dart';
import 'reflow_ocr_service.dart';

final reflowEngineProvider = Provider<ReflowEngine>((ref) => ReflowEngine());

class ReflowSettings {
  const ReflowSettings({
    this.detectTables = true,
    this.detectFigures = true,
    this.removeRepeatedHeaders = true,
    this.enableOcr = true,
  });

  final bool detectTables;
  final bool detectFigures;
  final bool removeRepeatedHeaders;
  final bool enableOcr;

  String get cacheKey => [
        detectTables ? 'tables' : 'no-tables',
        detectFigures ? 'figures' : 'no-figures',
        removeRepeatedHeaders
            ? 'clean-running-content'
            : 'keep-running-content',
        enableOcr ? 'ocr' : 'no-ocr',
      ].join('_');

  Map<String, Object> toJson() => {
        'detectTables': detectTables,
        'detectFigures': detectFigures,
        'removeRepeatedHeaders': removeRepeatedHeaders,
        'enableOcr': enableOcr,
      };
}

/// What happened to OCR while loading a document.
enum ReflowOcrStatus {
  /// The document has no pages that need OCR, or the Dart fallback was used.
  notNeeded,

  /// OCR is turned off in settings.
  disabled,

  /// Scanned pages were recognized and merged into the document.
  completed,

  /// OCR ran but found no text on the scanned pages. Not an error.
  emptyText,

  /// The OCR module is not installed yet.
  moduleMissing,

  /// This device cannot run OCR.
  unsupported,

  /// The load was cancelled (document closed). Nothing was published.
  cancelled,

  /// Recognition failed (timeout, permission, or unexpected error).
  failed,
}

/// A reflow document plus the outcome of OCR for it.
class ReflowLoadResult {
  const ReflowLoadResult(
    this.document, {
    this.ocrStatus = ReflowOcrStatus.notNeeded,
    this.ocrError,
  });

  final ReflowDocument document;
  final ReflowOcrStatus ocrStatus;
  final OcrException? ocrError;

  /// Pages that still lack text because OCR did not complete.
  bool get needsOcr => switch (ocrStatus) {
        ReflowOcrStatus.moduleMissing ||
        ReflowOcrStatus.unsupported ||
        ReflowOcrStatus.failed =>
          document.ocrPages.isNotEmpty,
        _ => false,
      };
}

class ReflowEngine {
  ReflowEngine({
    Future<Directory> Function()? cacheDirectory,
    NativeJobRuntime? nativeRuntime,
    ReflowOcrService? ocrService,
  })  : _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory,
        _nativeRuntime = nativeRuntime ?? NativeJobRuntime.tryOpen(),
        _ocrService = ocrService ?? ReflowOcrService();

  static const engineVersion = 4;
  final Future<Directory> Function() _cacheDirectory;
  final NativeJobRuntime? _nativeRuntime;
  final ReflowOcrService _ocrService;

  Future<ReflowDocument> load(
    String path, {
    ReflowSettings settings = const ReflowSettings(),
  }) async =>
      (await loadWithStatus(path, settings: settings)).document;

  /// Like [load] but also reports the OCR outcome so callers can show a
  /// download prompt instead of an empty page. When OCR cannot run, the
  /// native-text document is returned and the OCR result is not cached.
  Future<ReflowLoadResult> loadWithStatus(
    String path, {
    ReflowSettings settings = const ReflowSettings(),
    OcrCancellationToken? cancellation,
    void Function(OcrProgress progress)? onOcrProgress,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('PDF no longer exists', path);
    }
    final root = await _cacheDirectory();
    await root.create(recursive: true);
    final native = _nativeRuntime;
    if (native != null) {
      final pathKey =
          sha256.convert(utf8.encode(file.absolute.path)).toString();
      final nativeCache = File(p.join(
        root.path,
        'native_${pathKey}_v${engineVersion}_${settings.cacheKey}.json',
      ));
      try {
        final request = <String, dynamic>{
          'inputPath': path,
          'cachePath': nativeCache.path,
          'settingsKey': settings.cacheKey,
          ...settings.toJson(),
        };
        final result = await native.executeReflow(request: request);
        final document = ReflowDocument.fromJson(result);
        if (document.ocrPages.isEmpty) return ReflowLoadResult(document);
        if (!settings.enableOcr) {
          return ReflowLoadResult(document,
              ocrStatus: ReflowOcrStatus.disabled);
        }
        final outcome = await _ocrService.recognizePages(
          path,
          document.ocrPages,
          onProgress: onOcrProgress,
          cancellation: cancellation,
        );
        switch (outcome) {
          case OcrFailure(:final error):
            return ReflowLoadResult(
              document,
              ocrStatus: switch (error.kind) {
                OcrFailureKind.moduleMissing => ReflowOcrStatus.moduleMissing,
                OcrFailureKind.unsupportedDevice => ReflowOcrStatus.unsupported,
                OcrFailureKind.cancelled => ReflowOcrStatus.cancelled,
                _ => ReflowOcrStatus.failed,
              },
              ocrError: error,
            );
          case OcrOk(:final pages) || OcrEmptyText(:final pages):
            if (cancellation?.isCancelled ?? false) {
              return ReflowLoadResult(
                document,
                ocrStatus: ReflowOcrStatus.cancelled,
              );
            }
            final empty = outcome is OcrEmptyText;
            if (pages.isEmpty) {
              return ReflowLoadResult(document,
                  ocrStatus: ReflowOcrStatus.emptyText);
            }
            final completed = await native.executeReflow(request: {
              ...request,
              'ocrPages': pages,
            });
            return ReflowLoadResult(
              ReflowDocument.fromJson(completed),
              ocrStatus:
                  empty ? ReflowOcrStatus.emptyText : ReflowOcrStatus.completed,
            );
        }
      } on FormatException {
        // Older native libraries do not expose reflow; keep the Dart engine
        // available so app upgrades never make documents unreadable.
      } on NativeJobException catch (error) {
        if (error.error.code != 'native_backend_unavailable' &&
            error.error.code != 'unsupported_operation') {
          rethrow;
        }
      }
    }

    final hash = await sha256.bind(file.openRead()).first.then((v) => '$v');
    final cache = File(p.join(
      root.path,
      '${hash}_v${engineVersion}_${settings.cacheKey}.json',
    ));
    if (await cache.exists()) {
      try {
        final decoded = jsonDecode(await cache.readAsString());
        final document = ReflowDocument.fromJson(
          (decoded as Map).cast<String, dynamic>(),
        );
        if (document.fileHash == hash &&
            document.engineVersion == engineVersion &&
            document.settingsKey == settings.cacheKey) {
          return ReflowLoadResult(document);
        }
      } on Object {
        // A partial/stale cache is safe to replace from the source PDF.
      }
    }

    final encoded = await Isolate.run(() => _analyzePdf(
          path,
          hash,
          engineVersion,
          settings.cacheKey,
          settings.toJson(),
        ));
    final temporary = File('${cache.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    await temporary.rename(cache.path);
    return ReflowLoadResult(ReflowDocument.fromJson(
      (jsonDecode(encoded) as Map).cast<String, dynamic>(),
    ));
  }

  static Future<Directory> _defaultCacheDirectory() async => Directory(
        p.join((await getApplicationSupportDirectory()).path, 'reflow'),
      );
}

String _analyzePdf(
  String path,
  String hash,
  int version,
  String settingsKey,
  Map<String, Object> settings,
) {
  final document = sf.PdfDocument(inputBytes: File(path).readAsBytesSync());
  try {
    final pageCount = document.pages.count;
    final pageSizes = <int, Size>{
      for (var page = 0; page < pageCount; page++)
        page + 1: document.pages[page].size,
    };
    final extracted = sf.PdfTextExtractor(document).extractTextLines();
    final lines = extracted
        .where((line) => line.text.trim().isNotEmpty)
        .map(_LayoutLine.fromSyncfusion)
        .toList(growable: false);

    final repeated = settings['removeRepeatedHeaders'] == true
        ? _findRepeatedRunningContent(lines, pageSizes)
        : const <String>{};
    final blocks = <Map<String, Object?>>[];
    for (var page = 1; page <= pageCount; page++) {
      final size = pageSizes[page]!;
      final pageLines = lines
          .where((line) =>
              line.page == page && !repeated.contains(_runningKey(line.text)))
          .toList();
      final readingOrder = _readingOrder(pageLines, size.width);
      blocks.addAll(_buildTextBlocks(
        readingOrder,
        size,
        detectTables: settings['detectTables'] == true,
      ));
      if (settings['detectFigures'] == true) {
        blocks.addAll(_detectRenderedRegions(pageLines, size, page));
      }
      blocks.sort((a, b) {
        final aa = (a['anchor'] as Map)['page'] as int;
        final bb = (b['anchor'] as Map)['page'] as int;
        if (aa != bb) return aa.compareTo(bb);
        final ay = (((a['anchor'] as Map)['bounds'] as List)[1] as num);
        final by = (((b['anchor'] as Map)['bounds'] as List)[1] as num);
        return ay.compareTo(by);
      });
      blocks.add(_blockJson(
        type: ReflowBlockType.pageBreak,
        page: page,
        bounds: Rect.fromLTWH(0, size.height, size.width, 0),
      ));
    }
    return jsonEncode({
      'fileHash': hash,
      'engineVersion': version,
      'settingsKey': settingsKey,
      'pageCount': pageCount,
      'blocks': blocks,
    });
  } finally {
    document.dispose();
  }
}

class _LayoutLine {
  const _LayoutLine({
    required this.page,
    required this.text,
    required this.bounds,
    required this.fontName,
    required this.fontSize,
    required this.glyphs,
    required this.cells,
  });

  final int page;
  final String text;
  final Rect bounds;
  final String fontName;
  final double fontSize;
  final List<Map<String, Object>> glyphs;
  final List<String> cells;

  factory _LayoutLine.fromSyncfusion(sf.TextLine line) {
    final glyphs = <Map<String, Object>>[];
    for (final word in line.wordCollection) {
      for (final glyph in word.glyphs) {
        glyphs.add({
          'text': glyph.text,
          'bounds': _rectJson(glyph.bounds),
          'fontName': glyph.fontName,
          'fontSize': glyph.fontSize,
          // PDF extraction APIs do not expose an explicit baseline. The glyph
          // bottom is a stable baseline proxy and remains in source units.
          'baseline': glyph.bounds.bottom,
        });
      }
    }
    return _LayoutLine(
      page: line.pageIndex + 1,
      text: line.text.trim(),
      bounds: line.bounds,
      fontName: line.fontName,
      fontSize: line.fontSize,
      glyphs: glyphs,
      cells: _tableCells(line.wordCollection, line.fontSize, line.text),
    );
  }
}

List<String> _tableCells(
  List<sf.TextWord> words,
  double fontSize,
  String sourceText,
) {
  final explicitColumns = sourceText
      .trim()
      .split(RegExp(r'\s{2,}'))
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (explicitColumns.length > 1) return explicitColumns;
  if (words.length < 2) return const [];
  final sorted = [...words]
    ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  final cells = <String>[];
  var current = StringBuffer(sorted.first.text);
  var previous = sorted.first;
  var hasLargeGap = false;
  for (final word in sorted.skip(1)) {
    final gap = word.bounds.left - previous.bounds.right;
    if (gap > math.max(10, fontSize * 2.2)) {
      cells.add(current.toString().trim());
      current = StringBuffer(word.text);
      hasLargeGap = true;
    } else {
      current.write(' ${word.text}');
    }
    previous = word;
  }
  cells.add(current.toString().trim());
  return hasLargeGap && cells.length > 1 ? cells : const [];
}

Set<String> _findRepeatedRunningContent(
  List<_LayoutLine> lines,
  Map<int, Size> pageSizes,
) {
  if (pageSizes.length < 3) return const {};
  final pagesByText = <String, Set<int>>{};
  for (final line in lines) {
    final height = pageSizes[line.page]!.height;
    if (line.bounds.top > height * .13 && line.bounds.bottom < height * .88) {
      continue;
    }
    final key = _runningKey(line.text);
    if (key.length < 3) continue;
    pagesByText.putIfAbsent(key, () => <int>{}).add(line.page);
  }
  final threshold = math.max(2, (pageSizes.length * .6).ceil());
  return pagesByText.entries
      .where((entry) => entry.value.length >= threshold)
      .map((entry) => entry.key)
      .toSet();
}

String _runningKey(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<_LayoutLine> _readingOrder(List<_LayoutLine> source, double pageWidth) {
  final lines = [...source];
  int column(_LayoutLine line) {
    if (line.bounds.width > pageWidth * .68 ||
        (line.bounds.left < pageWidth * .48 &&
            line.bounds.right > pageWidth * .52)) {
      return 0;
    }
    return line.bounds.center.dx < pageWidth / 2 ? 1 : 2;
  }

  lines.sort((a, b) {
    final ac = column(a);
    final bc = column(b);
    final closeVertically = (a.bounds.top - b.bounds.top).abs() <
        math.max(a.fontSize, b.fontSize) * 3;
    if (closeVertically && ac != bc && ac != 0 && bc != 0) {
      return ac.compareTo(bc);
    }
    final vertical = a.bounds.top.compareTo(b.bounds.top);
    return vertical != 0 ? vertical : a.bounds.left.compareTo(b.bounds.left);
  });
  return lines;
}

List<Map<String, Object?>> _buildTextBlocks(
  List<_LayoutLine> lines,
  Size pageSize, {
  required bool detectTables,
}) {
  if (lines.isEmpty) return const [];
  final sizes = lines.map((line) => line.fontSize).where((v) => v > 0).toList()
    ..sort();
  final bodySize = sizes.isEmpty ? 11.0 : sizes[sizes.length ~/ 2];
  final blocks = <Map<String, Object?>>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (detectTables && line.cells.length > 1) {
      final rows = <List<String>>[line.cells];
      var bounds = line.bounds;
      var next = index + 1;
      while (next < lines.length && lines[next].cells.length > 1) {
        final candidate = lines[next];
        final gap = candidate.bounds.top - bounds.bottom;
        if (gap > math.max(bodySize * 2.8, 28) ||
            (candidate.cells.length - rows.first.length).abs() > 1) {
          break;
        }
        rows.add(candidate.cells);
        bounds = bounds.expandToInclude(candidate.bounds);
        next++;
      }
      if (rows.length >= 2) {
        blocks.add(_blockJson(
          type: ReflowBlockType.table,
          page: line.page,
          bounds: bounds,
          text: rows.map((row) => row.join(' | ')).join('\n'),
          rows: rows,
          glyphs: lines
              .sublist(index, next)
              .expand((value) => value.glyphs)
              .toList(),
        ));
        index = next;
        continue;
      }
    }

    final type = _classify(line, bodySize, pageSize.height);
    if (type == ReflowBlockType.paragraph) {
      var text = line.text;
      var bounds = line.bounds;
      final glyphs = [...line.glyphs];
      var next = index + 1;
      while (next < lines.length) {
        final candidate = lines[next];
        if (_classify(candidate, bodySize, pageSize.height) !=
            ReflowBlockType.paragraph) {
          break;
        }
        final gap = candidate.bounds.top - bounds.bottom;
        final aligned = (candidate.bounds.left - line.bounds.left).abs() <
            math.max(12, bodySize * 1.5);
        if (!aligned || gap > math.max(bodySize * 1.2, 16)) break;
        text = _joinWrapped(text, candidate.text);
        bounds = bounds.expandToInclude(candidate.bounds);
        glyphs.addAll(candidate.glyphs);
        next++;
      }
      blocks.add(_blockJson(
        type: type,
        page: line.page,
        bounds: bounds,
        text: text,
        glyphs: glyphs,
      ));
      index = next;
      continue;
    }

    blocks.add(_blockJson(
      type: type,
      page: line.page,
      bounds: line.bounds,
      text: line.text,
      glyphs: line.glyphs,
      headingLevel: type == ReflowBlockType.heading
          ? (line.fontSize >= bodySize * 1.7 ? 1 : 2)
          : null,
    ));
    index++;
  }
  return blocks;
}

ReflowBlockType _classify(_LayoutLine line, double body, double pageHeight) {
  final value = line.text.trim();
  final lowerFont = line.fontName.toLowerCase();
  if (_looksLikeEquation(value)) return ReflowBlockType.equation;
  if (RegExp(r'^(?:[•●▪◦‣–-]|\(?\d+[.)]|[a-zA-Z][.)])\s+').hasMatch(value)) {
    return ReflowBlockType.list;
  }
  if (line.fontSize >= body * 1.25 ||
      ((lowerFont.contains('bold') || lowerFont.contains('semibold')) &&
          value.length < 120)) {
    return ReflowBlockType.heading;
  }
  if (line.fontSize > 0 &&
      line.fontSize <= body * .78 &&
      line.bounds.top > pageHeight * .65) {
    return ReflowBlockType.footnote;
  }
  return ReflowBlockType.paragraph;
}

bool _looksLikeEquation(String text) {
  if (text.length > 160) return false;
  final symbols = RegExp(r'[=∑∫√≈≠≤≥±×÷^_]').allMatches(text).length;
  return symbols >= 2 ||
      (symbols == 1 && RegExp(r'[A-Za-z]\s*[=≈]\s*[-+\d(]').hasMatch(text));
}

String _joinWrapped(String first, String second) {
  if (first.endsWith('-') && !first.endsWith(' -')) {
    return '${first.substring(0, first.length - 1)}${second.trimLeft()}';
  }
  return '${first.trimRight()} ${second.trimLeft()}';
}

List<Map<String, Object?>> _detectRenderedRegions(
  List<_LayoutLine> lines,
  Size pageSize,
  int page,
) {
  if (lines.isEmpty) {
    return [
      _blockJson(
        type: ReflowBlockType.fallbackRegion,
        page: page,
        bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      ),
    ];
  }
  final ordered = [...lines]
    ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
  final regions = <Map<String, Object?>>[];
  var cursor = pageSize.height * .08;
  for (var i = 0; i <= ordered.length; i++) {
    final nextTop =
        i == ordered.length ? pageSize.height * .92 : ordered[i].bounds.top;
    final gap = nextTop - cursor;
    if (gap >= math.max(90, pageSize.height * .16)) {
      final before = i > 0 ? ordered[i - 1].text : '';
      final after = i < ordered.length ? ordered[i].text : '';
      final caption = _captionFrom(before, after);
      // Whitespace alone is not evidence of a figure. Uncaptioned, textless
      // pages are preserved by the full-page fallback above; mixed-content
      // regions require a nearby figure/chart caption to avoid blank cards.
      if (caption == null) {
        if (i < ordered.length) {
          cursor = math.max(cursor, ordered[i].bounds.bottom);
        }
        continue;
      }
      final type = RegExp(r'\b(chart|graph|plot)\b', caseSensitive: false)
              .hasMatch(caption)
          ? ReflowBlockType.chart
          : ReflowBlockType.image;
      regions.add(_blockJson(
        type: type,
        page: page,
        bounds: Rect.fromLTRB(
          pageSize.width * .06,
          cursor,
          pageSize.width * .94,
          nextTop,
        ),
        caption: caption,
      ));
    }
    if (i < ordered.length) cursor = math.max(cursor, ordered[i].bounds.bottom);
  }
  return regions;
}

String? _captionFrom(String before, String after) {
  final expression = RegExp(
    r'^\s*(?:fig(?:ure)?\.?|chart|graph|image)\s*\d*',
    caseSensitive: false,
  );
  if (expression.hasMatch(after)) return after.trim();
  if (expression.hasMatch(before)) return before.trim();
  return null;
}

Map<String, Object?> _blockJson({
  required ReflowBlockType type,
  required int page,
  required Rect bounds,
  String text = '',
  List<Map<String, Object>> glyphs = const [],
  List<List<String>> rows = const [],
  String? caption,
  int? headingLevel,
}) =>
    {
      'type': type.name,
      'anchor': {'page': page, 'bounds': _rectJson(bounds)},
      'text': text,
      'glyphs': glyphs,
      'rows': rows,
      'caption': caption,
      'headingLevel': headingLevel,
    };

List<double> _rectJson(Rect rect) =>
    [rect.left, rect.top, rect.right, rect.bottom];
