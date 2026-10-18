import 'package:flutter/material.dart';
import '../widgets/sheet/app_components.dart';

Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showAppBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
  );
}

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    elevation: 0,
    builder: (BuildContext context) {
      return AppBottomSheet(child: builder(context));
    },
  );
}
