import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class ArcOutlineNode extends StatefulWidget {
  const ArcOutlineNode({
    super.key,
    required this.node,
    required this.level,
    required this.onTap,
  });

  final PdfOutlineNode node;
  final int level;
  final void Function(int) onTap;

  @override
  State<ArcOutlineNode> createState() => _ArcOutlineNodeState();
}

class _ArcOutlineNodeState extends State<ArcOutlineNode> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = widget.node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (hasChildren) {
                setState(() => _isExpanded = !_isExpanded);
              } else if (widget.node.dest?.pageNumber != null) {
                widget.onTap(widget.node.dest!.pageNumber);
              }
            },
            child: Padding(
              padding: EdgeInsets.only(
                left: 24.0 + (widget.level * 16.0),
                right: 24.0,
                top: 12.0,
                bottom: 12.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.node.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: hasChildren ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (hasChildren)
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubicEmphasized,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubicEmphasized,
          alignment: Alignment.topCenter,
          child: _isExpanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.node.children
                      .map((child) => ArcOutlineNode(
                            node: child,
                            level: widget.level + 1,
                            onTap: widget.onTap,
                          ))
                      .toList(),
                )
              : const SizedBox(height: 0, width: double.infinity),
        ),
      ],
    );
  }
}
