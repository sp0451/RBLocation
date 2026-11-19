import 'package:clocation/app/data/models/geo/wgs84_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts geographic boundaries and trims input', () {
    expect(
      Wgs84Coordinate.parse(' 90 ', ' -180 '),
      Wgs84Coordinate(latitude: 90, longitude: -180),
    );
    expect(Wgs84Coordinate.parse('-90', '180').label, '-90.000000, 180.000000');
  });
  test('rejects non-finite, malformed and out-of-range coordinates', () {
    for (final latitude in ['NaN', 'Infinity', '91', '-91', '', 'abc']) {
      expect(() => Wgs84Coordinate.parse(latitude, '0'), throwsFormatException);
    }
    for (final longitude in ['NaN', '-Infinity', '181', '-181', '']) {
      expect(
        () => Wgs84Coordinate.parse('0', longitude),
        throwsFormatException,
      );
    }
  });
}
