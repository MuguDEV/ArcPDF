import 'package:flutter_test/flutter_test.dart';
import 'package:arcpdf/src/core/utils/fuzzy_search.dart';

void main() {
  group('isFuzzyMatch', () {
    test('empty query returns true', () {
      expect(isFuzzyMatch('some text', ''), isTrue);
    });

    test('exact substring match', () {
      expect(isFuzzyMatch('hello world', 'world'), isTrue);
    });

    test('a match with a small typo', () {
      expect(isFuzzyMatch('hello world', 'worl'), isTrue);
      expect(isFuzzyMatch('hello world', 'helo'), isTrue);
    });

    test('a multi-word query', () {
      expect(isFuzzyMatch('the quick brown fox', 'quick fox'), isTrue);
    });

    test('no match returns false', () {
      expect(isFuzzyMatch('hello world', 'xyz'), isFalse);
    });

    test('different casing', () {
      expect(isFuzzyMatch('HELLO WORLD', 'hello'), isTrue);
    });

    test('punctuation in the text', () {
      expect(isFuzzyMatch('hello, world!', 'world'), isTrue);
    });
  });

  group('levenshteinDistance', () {
    test('identical strings return 0', () {
      expect(levenshteinDistance('abc', 'abc'), 0);
    });

    test('empty first string returns the length of the second', () {
      expect(levenshteinDistance('', 'abc'), 3);
    });

    test('empty second string returns the length of the first', () {
      expect(levenshteinDistance('abc', ''), 3);
    });

    test('single insertion', () {
      expect(levenshteinDistance('ab', 'abc'), 1);
    });

    test('single deletion', () {
      expect(levenshteinDistance('abc', 'ab'), 1);
    });

    test('single substitution', () {
      expect(levenshteinDistance('abc', 'adc'), 1);
    });

    test('a completely different pair', () {
      expect(levenshteinDistance('abc', 'xyz'), 3);
    });

    test('symmetry (distance(a, b) == distance(b, a))', () {
      expect(levenshteinDistance('kitten', 'sitting'), levenshteinDistance('sitting', 'kitten'));
    });
  });
}
