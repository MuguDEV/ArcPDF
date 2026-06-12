import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  OpenTabsNotifier() : super(const OpenTabsState());

  void openTab(PdfFileItem item) {
    final tabs = List<PdfFileItem>.from(state.tabs);
    final index = tabs.indexWhere((t) => t.path == item.path);

    if (index != -1) {
      state = state.copyWith(activeIndex: index);
    } else {
      tabs.add(item);
      state = state.copyWith(tabs: tabs, activeIndex: tabs.length - 1);
    }
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;

    final tabs = List<PdfFileItem>.from(state.tabs)..removeAt(index);
    int newIndex = state.activeIndex;

    if (tabs.isEmpty) {
      newIndex = 0;
    } else if (newIndex >= index) {
      newIndex = newIndex > 0 ? newIndex - 1 : 0;
    }

    state = state.copyWith(tabs: tabs, activeIndex: newIndex);
  }

  void setActiveIndex(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeIndex: index);
    }
  }
}

final openTabsProvider = StateNotifierProvider<OpenTabsNotifier, OpenTabsState>((ref) {
  return OpenTabsNotifier();
});
