import 'package:flutter_test/flutter_test.dart';
import 'package:vimj_attendance/core/search_utils.dart';

void main() {
  group('matchesSearchQuery', () {
    test('matches multiple terms across attendance fields', () {
      expect(
          matchesSearchQuery(['Maya Sharma', 'Yoga', 'PRESENT'], 'maya yoga'),
          isTrue);
    });

    test('matches visible status labels to API status values', () {
      expect(matchesSearchQuery(['NOT_CONFIRM'], 'Not Confirm'), isTrue);
    });

    test('matches date values with common separators', () {
      expect(matchesSearchQuery(['2026-10-07'], '2026/10/07'), isTrue);
    });

    test('rejects a query when any term is missing', () {
      expect(
          matchesSearchQuery(['Maya Sharma', 'Yoga'], 'maya ballet'), isFalse);
    });

    test('matches an empty query to all rows', () {
      expect(matchesSearchQuery(['Maya Sharma'], '   '), isTrue);
    });
  });
}
