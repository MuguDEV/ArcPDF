import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';

class DynamicIslandNotification extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismissed;

  const DynamicIslandNotification({
    super.key,
    required this.message,
    this.icon,
    this.duration = const Duration(seconds: 3),
    required this.onDismissed,
  });

  static void show(BuildContext context, String message, {IconData? icon, Duration duration = const Duration(seconds: 3)}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => DynamicIslandNotification(
        message: message,
        icon: icon,
        duration: duration,
        onDismissed: () {
          entry.remove();
        },
      ),
    );

    overlay.insert(entry);
  }

  @override
  State<DynamicIslandNotification> createState() => _DynamicIslandNotificationState();
}

class _DynamicIslandNotificationState extends State<DynamicIslandNotification> {
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) {
        setState(() {
          _isDismissing = true;
        });
        Future.delayed(const Duration(milliseconds: 400), widget.onDismissed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (_isDismissing) {
      return content.animate().slideY(begin: 0, end: -2.0, duration: 350.ms, curve: Curves.easeInBack).scale(end: const Offset(0.8, 0.8), duration: 350.ms).fadeOut(duration: 200.ms);
    }

    return content.animate().slideY(begin: -2.0, end: 0, duration: 600.ms, curve: Curves.elasticOut).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 600.ms, curve: Curves.elasticOut).fadeIn(duration: 300.ms);
  }
}
