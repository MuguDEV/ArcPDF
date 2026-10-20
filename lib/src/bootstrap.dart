import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;

import 'data/local_boxes.dart';

import 'features/pdf/domain/pdf_annotation.dart';
import 'core/utils/logger.dart';
import 'core/utils/app_diagnostics.dart';

Future<void> bootstrap() async {
  AppDiagnostics.instance.install();
  final timer = Stopwatch()..start();
  await AppLogger.event('bootstrap.started');
  try {
    await Hive.initFlutter();
    await AppLogger.init();
    await pdfrxFlutterInitialize();
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PdfAnnotationAdapter());
    }
    await Hive.openBox<String>(LocalBoxes.favorites);
    await Hive.openBox<String>(LocalBoxes.recents);
    await Hive.openBox(LocalBoxes.settings);
    await Hive.openBox<String>(LocalBoxes.thumbnailCache);
    await Hive.openBox<int>(LocalBoxes.recentsTimestamps);
    await Hive.openBox<List<String>>(LocalBoxes.tags);
    await Hive.openBox<dynamic>(LocalBoxes.sessions);
    await Hive.openBox<PdfAnnotation>('pdf_annotations');
    await Hive.openBox<int>('reading_progress_pages');
    await Hive.openBox<double>('reading_progress_zoom');
    await Hive.openBox<int>('reading_progress_time');

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
