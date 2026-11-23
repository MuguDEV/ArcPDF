import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ArcPDF's brand monogram.
///
/// Functional document and action icons continue to use [ArcIcons]; this mark
/// is reserved for app identity so branding stays consistent and meaningful.
class ArcPdfMark extends StatelessWidget {
  const ArcPdfMark({
    super.key,
    this.size = 32,
    this.color,
    this.semanticLabel = 'ArcPDF',
  });

  final double size;
  final Color? color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: SvgPicture.asset(
            'assets/brand/arcpdf_monogram.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(
              color ?? Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
        ),
      );
}
