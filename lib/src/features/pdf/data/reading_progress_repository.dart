import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>((ref) => ReadingProgressRepository());

class ReadingProgressRepository {
  Box<int> get _pageBox => Hive.box<int>('reading_progress_pages');
  Box<int> get _timeBox => Hive.box<int>('reading_progress_time');

  int getLastReadPage(String pdfPath) {
    return _pageBox.get(pdfPath) ?? 1;
  }

  Future<void> saveLastReadPage(String pdfPath, int page) async {
    await _pageBox.put(pdfPath, page);
  }

  int getTotalReadTime(String pdfPath) {
    return _timeBox.get(pdfPath) ?? 0;
  }

  Future<void> addReadTime(String pdfPath, int seconds) async {
    final current = getTotalReadTime(pdfPath);
    await _timeBox.put(pdfPath, current + seconds);
  }
}
