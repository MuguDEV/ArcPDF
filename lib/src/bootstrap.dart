import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import 'data/local_boxes.dart';

import 'features/pdf/domain/pdf_annotation.dart';
import 'core/utils/logger.dart';
import 'core/utils/app_diagnostics.dart';

class MetadataRepairRequired implements Exception {
  const MetadataRepairRequired(this.boxName, this.cause);

  final String boxName;
  final Object cause;
}

Future<void> bootstrap({bool repairMetadata = false}) async {
  AppDiagnostics.instance.install();
  final timer = Stopwatch()..start();
  await AppLogger.event('bootstrap.started');
  try {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PdfAnnotationAdapter());
    }
    // Open sequentially so a failed retry cannot race another Hive open. Never
    // erase local metadata unless the user explicitly selects repair.
    await _openMetadataBox<String>(LocalBoxes.favorites, repairMetadata);
    await _openMetadataBox<String>(LocalBoxes.recents, repairMetadata);
    await _openMetadataBox<dynamic>(LocalBoxes.settings, repairMetadata);
    await _openMetadataBox<String>(LocalBoxes.thumbnailCache, repairMetadata);
    await _openMetadataBox<int>(LocalBoxes.recentsTimestamps, repairMetadata);
    await _openMetadataBox<List<String>>(LocalBoxes.tags, repairMetadata);
    await _openMetadataBox<dynamic>(LocalBoxes.sessions, repairMetadata);
    await _openMetadataBox<PdfAnnotation>('pdf_annotations', repairMetadata);
    await _openMetadataBox<int>('reading_progress_pages', repairMetadata);
    await _openMetadataBox<double>('reading_progress_zoom', repairMetadata);
    await _openMetadataBox<int>('reading_progress_time', repairMetadata);

    // Logging is diagnostic and PDFium initializes lazily when a document is
    // first opened. Neither should delay access to the library UI.
    unawaited(AppLogger.init());

    await AppLogger.event('bootstrap.completed',
        fields: {'elapsedMs': timer.elapsedMilliseconds});
  } catch (error, stack) {
    // If Hive itself failed, the logger can still try its file-only fallback.
    await AppLogger.init();
    await AppLogger.error('bootstrap.failed', error, stack);
    await AppLogger.flush();
    rethrow;
  }
}

Future<void> _openMetadataBox<T>(String name, bool repairMetadata) async {
  if (Hive.isBoxOpen(name)) {
    Hive.box<T>(name);
    return;
  }
  try {
    await Hive.openBox<T>(name);
  } on HiveError catch (error) {
    if (!repairMetadata) throw MetadataRepairRequired(name, error);
    await Hive.deleteBoxFromDisk(name);
    await Hive.openBox<T>(name);
    await AppLogger.warning('bootstrap.metadata_box_repaired');
  }
}
