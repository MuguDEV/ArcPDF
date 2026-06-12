import 'dart:ui';
import 'package:flutter/material.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';

class PeekOverlay extends StatefulWidget {
  final PdfFileItem item;
  final VoidCallback onDismiss;

  const PeekOverlay({super.key, required this.item, required this.onDismiss});

  @override
  State<PeekOverlay> createState() => _PeekOverlayState();
}

class _PeekOverlayState extends State<PeekOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _controller.forward();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTapUp: (_) => _dismiss(),
      onPanEnd: (_) => _dismiss(),
      onLongPressEnd: (_) => _dismiss(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final val = Curves.easeOutCubic.transform(_controller.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Blurred background
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16 * val, sigmaY: 16 * val),
                child: Container(color: Colors.black.withValues(alpha: 0.3 * val)),
              ),

              // Center Peek Card
              Center(
                child: Transform.scale(
                  scale: 0.85 + (0.15 * val),
                  child: Opacity(
                    opacity: val,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                )
                              ]
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 1 / 1.4,
                                child: PdfThumbnail(
                                  path: widget.item.path,
                                  isEncrypted: widget.item.isEncrypted,
                                  isCorrupted: widget.item.isCorrupted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.item.name,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}
