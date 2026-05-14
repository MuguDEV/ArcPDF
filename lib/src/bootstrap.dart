import 'package:hive_flutter/hive_flutter.dart';

import 'data/local_boxes.dart';

import 'features/pdf/domain/pdf_annotation.dart';
import 'core/utils/logger.dart';

Future<void> bootstrap() async {
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(PdfAnnotationAdapter());
  }
  await Hive.openBox<String>(LocalBoxes.favorites);
  await Hive.openBox<String>(LocalBoxes.recents);
  await Hive.openBox(LocalBoxes.settings);
  await Hive.openBox<String>(LocalBoxes.thumbnailCache);
  await Hive.openBox<int>(LocalBoxes.recentsTimestamps);
  await Hive.openBox<PdfAnnotation>('pdf_annotations');
  await Hive.openBox<int>('reading_progress_pages');
  await Hive.openBox<int>('reading_progress_time');

  // Initialize Logger
  await AppLogger.init();
}
