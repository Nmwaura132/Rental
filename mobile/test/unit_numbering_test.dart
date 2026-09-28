import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/features/properties/unit_numbering.dart';

void main() {
  group('layoutNumbers', () {
    test('floor + letter gives Maria Goretti its own numbering', () {
      expect(
        layoutNumbers(NumberingStyle.floorLetter, floors: 5, perFloor: 2, hasGround: true),
        ['G1', 'G2', '1A', '1B', '2A', '2B', '3A', '3B', '4A', '4B'],
      );
    });

    test('floor + number gives the 101, 102 layout', () {
      expect(
        layoutNumbers(NumberingStyle.floorNumber, floors: 2, perFloor: 2, hasGround: false),
        ['101', '102', '201', '202'],
      );
    });

    test('letter + number letters the floors from the bottom', () {
      expect(
        layoutNumbers(NumberingStyle.letterNumber, floors: 2, perFloor: 2, hasGround: true),
        ['A1', 'A2', 'B1', 'B2'],
      );
    });

    test('running numbers count through the whole building', () {
      expect(
        layoutNumbers(NumberingStyle.running, floors: 2, perFloor: 3, hasGround: true),
        ['1', '2', '3', '4', '5', '6'],
      );
    });

    test('without a ground floor, numbering starts on the first', () {
      expect(
        layoutNumbers(NumberingStyle.floorLetter, floors: 1, perFloor: 2, hasGround: false),
        ['1A', '1B'],
      );
    });
  });

  group('floorOf', () {
    test('G is the ground floor', () {
      expect(floorOf('G2', hasGround: true), 0);
    });

    test('3B is the third floor', () {
      expect(floorOf('3B', hasGround: true), 3);
    });

    test('201 is the second floor', () {
      expect(floorOf('201', hasGround: true), 2);
    });
  });
}
