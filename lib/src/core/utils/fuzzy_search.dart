int levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      int cost = (s1[i] == s2[j]) ? 0 : 1;
      v1[j + 1] = _min3(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
    }
    for (int j = 0; j < v0.length; j++) {
      v0[j] = v1[j];
    }
  }

  return v1[s2.length];
}

int _min3(int a, int b, int c) {
  if (a < b && a < c) return a;
  if (b < c) return b;
  return c;
}

bool isFuzzyMatch(String text, String query) {
  if (query.isEmpty) return true;
  if (text.contains(query)) return true;

  final textWords = text.split(RegExp(r'\W+')).where((w) => w.isNotEmpty).toList();
  final queryWords = query.split(RegExp(r'\W+')).where((w) => w.isNotEmpty).toList();

  for (final qw in queryWords) {
    bool wordMatched = false;
    for (final tw in textWords) {
      if (tw.contains(qw)) {
         wordMatched = true;
         break;
      }
      final dist = levenshteinDistance(qw, tw);
      // Allow 1 typo for short words (3-5 chars), 2 for long (>5 chars)
      final threshold = qw.length <= 2 ? 0 : (qw.length <= 5 ? 1 : 2);
      if (dist <= threshold) {
        wordMatched = true;
        break;
      }
    }
    if (!wordMatched) return false;
  }
  return true;
}
