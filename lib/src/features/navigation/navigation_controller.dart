import 'package:flutter_riverpod/flutter_riverpod.dart';

final splashDoneProvider = StateProvider<bool>((ref) => false);

class NavigationState {
  const NavigationState(this.index);
  final int index;
}

class NavigationController extends StateNotifier<NavigationState> {
  NavigationController() : super(const NavigationState(0));

  void setIndex(int index) => state = NavigationState(index);
}

final navigationControllerProvider = StateNotifierProvider<NavigationController, NavigationState>((ref) => NavigationController());
