import 'dart:io';

class PdfFileItem {
  PdfFileItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
    required this.locationLabel,
    this.isEncrypted = false,
    this.isCorrupted = false,
    this.pageCount,
    this.openedAt,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;
  final String locationLabel;
  final bool isEncrypted;
  final bool isCorrupted;
  final int? pageCount;
  final DateTime? openedAt;

  String get cacheKey => path.toLowerCase();

  PdfFileItem copyWith({DateTime? openedAt}) {
    return PdfFileItem(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      lastModified: lastModified,
      locationLabel: locationLabel,
      isEncrypted: isEncrypted,
      isCorrupted: isCorrupted,
      pageCount: pageCount,
      openedAt: openedAt ?? this.openedAt,
    );
  }

  static PdfFileItem fromFile(File file, {bool isEncrypted = false, bool isCorrupted = false}) {
    final stat = file.statSync();
    final p = file.path;
    final parts = p.split(Platform.pathSeparator);
    return PdfFileItem(
      path: p,
      name: parts.isEmpty ? p : parts.last,
      sizeBytes: stat.size,
      lastModified: stat.modified,
      locationLabel: parts.length > 1 ? parts[parts.length - 2] : 'Storage',
      isEncrypted: isEncrypted,
      isCorrupted: isCorrupted,
    );
  }
}
