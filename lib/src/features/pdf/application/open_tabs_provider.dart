import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/local_boxes.dart';
import '../../../core/utils/logger.dart';
import '../domain/pdf_file_item.dart';

class OpenTabsState {
  final List<PdfFileItem> tabs;
  final int activeIndex;

  const OpenTabsState({this.tabs = const [], this.activeIndex = 0});

  OpenTabsState copyWith({List<PdfFileItem>? tabs, int? activeIndex}) {
    return OpenTabsState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

class OpenTabsNotifier extends StateNotifier<OpenTabsState> {
  final Box<dynamic> _sessionBox;

  OpenTabsNotifier(this._sessionBox) : super(const OpenTabsState()) {
    _loadSession();
  }

  void _loadSession() {
    try {
      _restoreSession();
    } catch (error, stack) {
      AppLogger.error('tabs.restore.failed', error, stack);
    }
  }

  void _restoreSession() {
    final activeIndex = _sessionBox.get('activeIndex') as int? ?? 0;
    final List<dynamic>? pathsDynamic = _sessionBox.get('paths');

    if (pathsDynamic != null) {
      final paths = pathsDynamic.cast<String>();
      final activePath = activeIndex >= 0 && activeIndex < paths.length
          ? paths[activeIndex]
          : null;
      final List<PdfFileItem> loadedTabs = [];
      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          loadedTabs.add(PdfFileItem.fromFile(file,
              isEncrypted: false, isCorrupted: false));
        }
      }
      if (loadedTabs.isNotEmpty) {
        final restoredIndex =
            loadedTabs.indexWhere((tab) => tab.path == activePath);
        state = state.copyWith(
          tabs: loadedTabs,
          activeIndex: restoredIndex >= 0 ? restoredIndex : 0,
        );
      }
    }
    AppLogger.event('tabs.restored', fields: {
      'count': state.tabs.length,
      'missing': (pathsDynamic?.length ?? 0) - state.tabs.length,
      'activeIndex': state.activeIndex,
    });
  }

  void _saveSession() {
    final activeIndex = state.activeIndex;
    final paths = state.tabs.map((e) => e.path).toList();
    unawaited(_persistSession(activeIndex, paths));
  }

  Future<void> _persistSession(int activeIndex, List<String> paths) async {
    try {
      await _sessionBox.putAll({'activeIndex': activeIndex, 'paths': paths});
    } catch (error, stack) {
      await AppLogger.error('tabs.session_save.failed', error, stack);
    }
  }

  void openTab(PdfFileItem item) {
    final tabs = List<PdfFileItem>.from(state.tabs);
    final index = tabs.indexWhere((t) => t.path == item.path);

    if (index != -1) {
      state = state.copyWith(activeIndex: index);
    } else {
      tabs.add(item);
      state = state.copyWith(tabs: tabs, activeIndex: tabs.length - 1);
    }
    AppLogger.event(index == -1 ? 'tabs.opened' : 'tabs.activated', fields: {
      'documentId': AppLogger.documentId(item.path),
      'count': state.tabs.length,
      'activeIndex': state.activeIndex,
    });
    _saveSession();
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;

    final closed = state.tabs[index];
    final tabs = List<PdfFileItem>.from(state.tabs)..removeAt(index);
    int newIndex = state.activeIndex;

    if (tabs.isEmpty) {
      newIndex = 0;
      state = const OpenTabsState(tabs: [], activeIndex: 0);
    } else {
      if (newIndex >= index) {
        newIndex = newIndex > 0 ? newIndex - 1 : 0;
      }
      state = state.copyWith(tabs: tabs, activeIndex: newIndex);
    }
    AppLogger.event('tabs.closed', fields: {
      'documentId': AppLogger.documentId(closed.path),
      'count': state.tabs.length,
      'activeIndex': state.activeIndex,
    });
    _saveSession();
  }

  void setActiveIndex(int index) {
    if (index >= 0 && index < state.tabs.length && index != state.activeIndex) {
      state = state.copyWith(activeIndex: index);
      AppLogger.event('tabs.activated', fields: {
        'documentId': AppLogger.documentId(state.tabs[index].path),
        'activeIndex': index,
      });
      _saveSession();
    }
  }
}

final openTabsProvider =
    StateNotifierProvider<OpenTabsNotifier, OpenTabsState>((ref) {
  final box = Hive.box<dynamic>(LocalBoxes.sessions);
  return OpenTabsNotifier(box);
});
