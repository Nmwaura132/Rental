import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/utils/text.dart';

void main() {
  group('sentenceCase', () {
    test('turns API status codes into readable text', () {
      expect(sentenceCase('in_progress'), 'In progress');
      expect(sentenceCase('partially_paid'), 'Partially paid');
      expect(sentenceCase('PAID'), 'Paid');
      expect(sentenceCase('overdue'), 'Overdue');
    });

    test('is safe on empty and padded input', () {
      expect(sentenceCase(''), '');
      expect(sentenceCase('   '), '');
      expect(sentenceCase('  open  '), 'Open');
    });

    test('does not change already-correct text', () {
      expect(sentenceCase('Open'), 'Open');
    });
  });
}
