import 'dart:ui';

enum ReflowBlockType {
  heading,
  paragraph,
  list,
  table,
  image,
  chart,
  equation,
  footnote,
  pageBreak,
  fallbackRegion,
}

class ReflowSourceAnchor {
  const ReflowSourceAnchor({required this.page, required this.bounds});

  final int page;
  final Rect bounds;

  Map<String, Object> toJson() => {
        'page': page,
        'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
      };

  factory ReflowSourceAnchor.fromJson(Map<String, dynamic> json) {
    final values = (json['bounds'] as List).cast<num>();
    return ReflowSourceAnchor(
      page: json['page'] as int,
      bounds: Rect.fromLTRB(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      ),
    );
  }
}

class ReflowGlyph {
  const ReflowGlyph({
    required this.text,
    required this.bounds,
    required this.fontName,
    required this.fontSize,
    required this.baseline,
  });

  final String text;
  final Rect bounds;
  final String fontName;
  final double fontSize;
  final double baseline;

  Map<String, Object> toJson() => {
        'text': text,
        'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
        'fontName': fontName,
        'fontSize': fontSize,
        'baseline': baseline,
      };

  factory ReflowGlyph.fromJson(Map<String, dynamic> json) {
    final values = (json['bounds'] as List).cast<num>();
    return ReflowGlyph(
      text: json['text'] as String,
      bounds: Rect.fromLTRB(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      ),
      fontName: json['fontName'] as String? ?? '',
      fontSize: (json['fontSize'] as num).toDouble(),
      baseline: (json['baseline'] as num).toDouble(),
    );
  }
}

class ReflowBlock {
  const ReflowBlock({
    required this.type,
    required this.anchor,
    this.text = '',
    this.glyphs = const [],
    this.rows = const [],
    this.caption,
    this.headingLevel,
    this.confidence = 1,
  });

  final ReflowBlockType type;
  final ReflowSourceAnchor anchor;
  final String text;
  final List<ReflowGlyph> glyphs;
  final List<List<String>> rows;
  final String? caption;
  final int? headingLevel;
  final double confidence;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'anchor': anchor.toJson(),
        'text': text,
        'glyphs': glyphs.map((glyph) => glyph.toJson()).toList(),
        'rows': rows,
        'caption': caption,
        'headingLevel': headingLevel,
        'confidence': confidence,
      };

  factory ReflowBlock.fromJson(Map<String, dynamic> json) => ReflowBlock(
        type: ReflowBlockType.values.byName(json['type'] as String),
        anchor: ReflowSourceAnchor.fromJson(
          (json['anchor'] as Map).cast<String, dynamic>(),
        ),
        text: json['text'] as String? ?? '',
        glyphs: (json['glyphs'] as List? ?? const [])
            .map((value) => ReflowGlyph.fromJson(
                  (value as Map).cast<String, dynamic>(),
                ))
            .toList(growable: false),
        rows: (json['rows'] as List? ?? const [])
            .map((row) => (row as List).cast<String>())
            .toList(growable: false),
        caption: json['caption'] as String?,
        headingLevel: json['headingLevel'] as int?,
        confidence: (json['confidence'] as num? ?? 1).toDouble(),
      );
}

class ReflowDocument {
  const ReflowDocument({
    required this.fileHash,
    required this.engineVersion,
    required this.settingsKey,
    required this.pageCount,
    required this.blocks,
    this.ocrPages = const [],
  });

  final String fileHash;
  final int engineVersion;
  final String settingsKey;
  final int pageCount;
  final List<ReflowBlock> blocks;
  final List<int> ocrPages;

  List<ReflowBlock> blocksForPage(int page) => blocks
      .where((block) => block.anchor.page == page)
      .toList(growable: false);

  Map<String, Object> toJson() => {
        'fileHash': fileHash,
        'engineVersion': engineVersion,
        'settingsKey': settingsKey,
        'pageCount': pageCount,
        'blocks': blocks.map((block) => block.toJson()).toList(),
        'ocrPages': ocrPages,
      };

  factory ReflowDocument.fromJson(Map<String, dynamic> json) => ReflowDocument(
        fileHash: json['fileHash'] as String,
        engineVersion: json['engineVersion'] as int,
        settingsKey: json['settingsKey'] as String,
        pageCount: json['pageCount'] as int,
        blocks: (json['blocks'] as List)
            .map((value) => ReflowBlock.fromJson(
                  (value as Map).cast<String, dynamic>(),
                ))
            .toList(growable: false),
        ocrPages: (json['ocrPages'] as List? ?? const []).cast<int>(),
      );
}
