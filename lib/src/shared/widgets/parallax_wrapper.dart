import 'package:flutter/material.dart';

class ParallaxWrapper extends StatelessWidget {
  final Widget child;
  final ScrollController scrollController;
  final GlobalKey listItemKey;
  final double parallaxSpeed;

  const ParallaxWrapper({
    super.key,
    required this.child,
    required this.scrollController,
    required this.listItemKey,
    this.parallaxSpeed = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, childWidget) {
        double offset = 0;
        if (listItemKey.currentContext != null) {
          final renderObject = listItemKey.currentContext!.findRenderObject();
          if (renderObject is RenderBox) {
            final position = renderObject.localToGlobal(Offset.zero).dy;
            final screenHeight = MediaQuery.of(context).size.height;
            final centerOffset = (position - (screenHeight / 2));
            offset = centerOffset * parallaxSpeed;
          }
        }
        return Transform.translate(
          offset: Offset(0, offset),
          child: childWidget,
        );
      },
      child: child,
    );
  }
}
