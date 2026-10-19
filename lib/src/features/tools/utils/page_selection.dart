/// Parse the complete selection or reject it; never silently drop bad tokens.
/// [pageCount] bounds expansion before allocating ranges.
List<int> parsePageSelection(String input, {required int pageCount}) {
  final pages = <int>{};
  for (final token in input.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(token);
    if (match == null) throw const FormatException('Invalid page selection');
    final start = int.tryParse(match[1]!);
    final end = int.tryParse(match[2] ?? match[1]!);
    if (start == null ||
        end == null ||
        start < 1 ||
        end < start ||
        end > pageCount) {
      throw const FormatException('Page selection is outside the document');
    }
    for (var page = start; page <= end; page++) {
      pages.add(page);
    }
  }
  return pages.toList();
}
