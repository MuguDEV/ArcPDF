import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/pdf_annotation.dart';

import 'package:flutter/foundation.dart';

final annotationRepositoryProvider =
    ChangeNotifierProvider<AnnotationRepository>(
        (ref) => AnnotationRepository());

class AnnotationRepository extends ChangeNotifier {
  Box<PdfAnnotation>? get _box {
    // Widget tests and early startup can construct the provider before the
    // bootstrap box is opened. The production bootstrap still opens this box
    // before any document can be annotated.
    if (!Hive.isBoxOpen('pdf_annotations')) return null;
    return Hive.box<PdfAnnotation>('pdf_annotations');
  }

  List<PdfAnnotation> getAnnotationsForPdf(String pdfPath) {
    final box = _box;
    if (box == null) return const [];
    return box.values.where((a) => a.pdfPath == pdfPath).toList();
  }

  List<PdfAnnotation> getAnnotationsForPage(String pdfPath, int pageNumber) {
    final box = _box;
    if (box == null) return const [];
    return box.values
        .where((a) => a.pdfPath == pdfPath && a.pageNumber == pageNumber)
        .toList();
  }

  Future<void> addAnnotation(PdfAnnotation annotation) async {
    final box = _box;
    if (box == null) return;
    await box.put(annotation.id, annotation);
    notifyListeners();
  }

  Future<void> updateAnnotation(PdfAnnotation annotation) async {
    final box = _box;
    if (box == null) return;
    await box.put(annotation.id, annotation);
    notifyListeners();
  }

  Future<void> deleteAnnotation(String id) async {
    final box = _box;
    if (box == null) return;
    await box.delete(id);
    notifyListeners();
  }

  Future<void> deleteAllAnnotationsForPdf(String pdfPath) async {
    final box = _box;
    if (box == null) return;
    final toDelete =
        box.values.where((a) => a.pdfPath == pdfPath).map((a) => a.id).toList();
    if (toDelete.isNotEmpty) {
      await box.deleteAll(toDelete);
      notifyListeners();
    }
  }

  Future<void> migratePdfPath(String oldPath, String newPath) async {
    final box = _box;
    if (box == null) return;
    final annotations = box.values.where((a) => a.pdfPath == oldPath).toList();
    for (final annotation in annotations) {
      await box.put(annotation.id, annotation.copyWith(pdfPath: newPath));
    }
    if (annotations.isNotEmpty) notifyListeners();
  }
}
