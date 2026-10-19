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
    if (!kDebugMode) {
      return super.buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }

    // Synchronous timeline spans must close before returning to the event loop.
    return Timeline.timeSync(
      'RouteTransition.build: ${route.settings.name ?? 'unknown'}',
      () => super.buildTransitions(
          route, context, animation, secondaryAnimation, child),
    );
  }
}
