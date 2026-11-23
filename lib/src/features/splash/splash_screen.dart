import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/navigation_controller.dart';
import '../../shared/widgets/arc_pdf_mark.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) ref.read(splashDoneProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF141414)
        : theme.colorScheme.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArcPdfMark(size: 112)
                .animate()
                .fadeIn(duration: 180.ms)
                .scale(begin: const Offset(0.96, 0.96), duration: 180.ms),
            const SizedBox(height: 22),
            Text(
              'ArcPDF',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ).animate().fadeIn(delay: 80.ms, duration: 180.ms),
            const SizedBox(height: 6),
            Text(
              'Your local PDF workspace',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ).animate().fadeIn(delay: 140.ms, duration: 180.ms),
          ],
        ),
      ),
    );
  }
}
