import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/pdf_annotation.dart';

final annotationRepositoryProvider = Provider<AnnotationRepository>((ref) => AnnotationRepository());

class AnnotationRepository {
  Box<PdfAnnotation> get _box => Hive.box<PdfAnnotation>('pdf_annotations');

  List<PdfAnnotation> getAnnotationsForPdf(String pdfPath) {
    return _box.values.where((a) => a.pdfPath == pdfPath).toList();
  }

  List<PdfAnnotation> getAnnotationsForPage(String pdfPath, int pageNumber) {
    return _box.values.where((a) => a.pdfPath == pdfPath && a.pageNumber == pageNumber).toList();
  }

  Future<void> addAnnotation(PdfAnnotation annotation) async {
    await _box.put(annotation.id, annotation);
  }

  Future<void> updateAnnotation(PdfAnnotation annotation) async {
    await _box.put(annotation.id, annotation);
  }

  Future<void> deleteAnnotation(String id) async {
    await _box.delete(id);
  }

  Future<void> deleteAllAnnotationsForPdf(String pdfPath) async {
    final toDelete = _box.values.where((a) => a.pdfPath == pdfPath).map((a) => a.id).toList();
    if (toDelete.isNotEmpty) {
      await _box.deleteAll(toDelete);
    }
  }
}
