import 'package:hive/hive.dart';

part 'pdf_annotation.g.dart';

@HiveType(typeId: 2)
class PdfAnnotation {
  PdfAnnotation({
    required this.id,
    required this.pdfPath,
    required this.pageNumber,
    required this.type,
    required this.color,
    required this.bounds,
    this.content,
    required this.createdAt,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String pdfPath;

  @HiveField(2)
  final int pageNumber;

  @HiveField(3)
  final String type; // 'highlight', 'note'

  @HiveField(4)
  final int color; // ARGB value

  @HiveField(5)
  final List<double> bounds; // [left, top, right, bottom] in page coordinates

  @HiveField(6)
  final String? content; // Text content for sticky notes

  @HiveField(7)
  final DateTime createdAt;

  PdfAnnotation copyWith({
    String? content,
    int? color,
  }) {
    return PdfAnnotation(
      id: id,
      pdfPath: pdfPath,
      pageNumber: pageNumber,
      type: type,
      color: color ?? this.color,
      bounds: bounds,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }
}
