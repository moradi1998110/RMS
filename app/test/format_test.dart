import 'package:flutter_test/flutter_test.dart';
import 'package:rms/core/format.dart';

void main() {
  group('points', () {
    test('the word agrees with the number, as Arabic needs', () {
      expect(points(1), 'نقطة واحدة');
      expect(points(2), 'نقطتان');
      expect(points(3), '3 نقاط');
      expect(points(10), '10 نقاط');
      expect(points(11), '11 نقطة');
      expect(points(6000), '6,000 نقطة');
      expect(points(0), '0 نقطة');
    });

    test('keeps the sign of a deduction', () {
      expect(points(-6000), '-6,000 نقطة');
      expect(points(-5), '-5 نقاط');
    });

    test('the word alone, for a number shown large beside it', () {
      expect(pointsWord(50000), 'نقطة');
      expect(pointsWord(7), 'نقاط');
    });
  });
}
