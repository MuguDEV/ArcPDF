import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';

final splashDoneProvider = StateProvider<bool>((ref) => false);

class NavigationState {
  const NavigationState(this.index);
  final int index;
}

class NavigationController extends StateNotifier<NavigationState> {
  NavigationController() : super(const NavigationState(0));

  static const _destinations = [
    'home',
    'favorites',
    'recent',
    'tools',
    'settings'
  ];

  void setIndex(int index) {
    if (index < 0 || index >= _destinations.length) {
      AppLogger.warning('navigation.invalid_destination');
      return;
    }
    if (index == state.index) return;
    final previous = state.index;
    state = NavigationState(index);
    AppLogger.event('navigation.destination', fields: {
      'from': _destinations[previous],
      'to': _destinations[index],
    });
  }
}

final navigationControllerProvider =
    StateNotifierProvider<NavigationController, NavigationState>(
        (ref) => NavigationController());
