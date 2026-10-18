import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:developer';

class TracedZoomPageTransitionsBuilder extends ZoomPageTransitionsBuilder {
  const TracedZoomPageTransitionsBuilder(
      {super.allowEnterRouteSnapshotting = false});

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (kDebugMode &&
        animation.status == AnimationStatus.forward &&
        animation.value == 0.0) {
      Timeline.startSync(
          'RouteTransition: ${route.settings.name ?? 'unknown'}');
    }
    if (kDebugMode && animation.isCompleted) {
      Timeline.finishSync();
    }

    // Add status listener to cleanly finish sync if it completes normally, but this is simple enough.
    // The BouncingScrollPhysics uses pure math.

    return super
        .buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}
