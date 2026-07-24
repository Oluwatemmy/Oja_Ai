import 'package:flutter_test/flutter_test.dart';
import 'package:ojaai/domain/use_cases/calculator.dart';

void main() {
  group('Calculator', () {
    test('evaluates basic arithmetic', () {
      expect(Calculator.evaluate('3 * 1800'), 5400);
      expect(Calculator.evaluate('9000 - 300'), 8700);
      expect(Calculator.evaluate('2 + 3 * 4'), 14);
      expect(Calculator.evaluate('(2 + 3) * 4'), 20);
      expect(Calculator.evaluate('10 / 4'), 2.5);
    });

    test('handles negative numbers and commas', () {
      expect(Calculator.evaluate('-5 + 10'), 5);
      expect(Calculator.evaluate('12,500 + 6,000'), 18500);
    });

    test('rejects garbage', () {
      expect(() => Calculator.evaluate('rm -rf'), throwsFormatException);
      expect(() => Calculator.evaluate('2 +'), throwsFormatException);
      expect(() => Calculator.evaluate('(2 + 3'), throwsFormatException);
      expect(() => Calculator.evaluate('5 / 0'), throwsFormatException);
    });
  });
}
