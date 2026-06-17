import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/local_boxes.dart';
import '../domain/pdf_file_item.dart';
import 'pdf_library_controller.dart';

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
    final activeIndex = _sessionBox.get('activeIndex') as int? ?? 0;
    final List<dynamic>? pathsDynamic = _sessionBox.get('paths');

    if (pathsDynamic != null) {
       final paths = pathsDynamic.cast<String>();
       final List<PdfFileItem> loadedTabs = [];
       for (final path in paths) {
         final file = File(path);
         if (file.existsSync()) {
           loadedTabs.add(PdfFileItem.fromFile(file, isEncrypted: false, isCorrupted: false));
         }
       }
       if (loadedTabs.isNotEmpty) {
         state = state.copyWith(tabs: loadedTabs, activeIndex: activeIndex < loadedTabs.length ? activeIndex : 0);
       }
    }
  }

  void _saveSession() {
    _sessionBox.put('activeIndex', state.activeIndex);
    _sessionBox.put('paths', state.tabs.map((e) => e.path).toList());
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
    _saveSession();
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;

    final tabs = List<PdfFileItem>.from(state.tabs)..removeAt(index);
    int newIndex = state.activeIndex;

    if (tabs.isEmpty) {
      newIndex = 0;
      state = OpenTabsState(tabs: [], activeIndex: 0);
    } else {
      if (newIndex >= index) {
        newIndex = newIndex > 0 ? newIndex - 1 : 0;
      }
      state = state.copyWith(tabs: tabs, activeIndex: newIndex);
    }
    _saveSession();
  }

  void setActiveIndex(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeIndex: index);
      _saveSession();
    }
  }
}

final openTabsProvider = StateNotifierProvider<OpenTabsNotifier, OpenTabsState>((ref) {
  final box = Hive.box<dynamic>(LocalBoxes.sessions);
  return OpenTabsNotifier(box);
});
