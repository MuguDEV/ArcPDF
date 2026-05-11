import 'package:hive_flutter/hive_flutter.dart';

import 'data/local_boxes.dart';

Future<void> bootstrap() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(LocalBoxes.favorites);
  await Hive.openBox<String>(LocalBoxes.recents);
  await Hive.openBox(LocalBoxes.settings);
  await Hive.openBox<String>(LocalBoxes.thumbnailCache);
  await Hive.openBox<int>(LocalBoxes.recentsTimestamps);
}
