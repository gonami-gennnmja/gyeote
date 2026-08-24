import 'package:flutter_test/flutter_test.dart';
import 'package:gyeote/features/location/data/models/geo_point.dart';

void main() {
  group('GeoPoint.parse / tryParse', () {
    // 127.027619(경도) / 37.497952(위도), SRID=4326 포함 EWKB(hex).
    // python struct(little-endian double)로 생성해 값을 교차 검증함:
    //   0101000020E6100000 + lng(8B) + lat(8B)
    const ewkbHexWithSrid =
        '0101000020e6100000e36f7b82c4c15f40287d21e4bcbf4240';
    // SRID 플래그 없이 인코딩한 동일 좌표 (일부 postgis 설정에서 발생 가능).
    const ewkbHexNoSrid = '0101000000e36f7b82c4c15f40287d21e4bcbf4240';
    // 음수 경도/위도(서반구/남반구) 케이스: -58.3816 / -34.6037.
    const ewkbHexNegative =
        '0101000020e6100000a913d044d8304dc0304ca60a464d41c0';

    test('parses EWKB hex with SRID flag', () {
      final point = GeoPoint.parse(ewkbHexWithSrid);
      expect(point.longitude, closeTo(127.027619, 1e-6));
      expect(point.latitude, closeTo(37.497952, 1e-6));
    });

    test('parses WKB hex without SRID flag', () {
      final point = GeoPoint.parse(ewkbHexNoSrid);
      expect(point.longitude, closeTo(127.027619, 1e-6));
      expect(point.latitude, closeTo(37.497952, 1e-6));
    });

    test('parses negative longitude/latitude correctly', () {
      final point = GeoPoint.parse(ewkbHexNegative);
      expect(point.longitude, closeTo(-58.3816, 1e-4));
      expect(point.latitude, closeTo(-34.6037, 1e-4));
    });

    test('parses WKT string', () {
      final point = GeoPoint.parse('POINT(127.0 37.5)');
      expect(point.longitude, 127.0);
      expect(point.latitude, 37.5);
    });

    test('parses EWKT string with SRID prefix', () {
      final point = GeoPoint.parse('SRID=4326;POINT(127.0 37.5)');
      expect(point.longitude, 127.0);
      expect(point.latitude, 37.5);
    });

    test('parses GeoJSON map', () {
      final point = GeoPoint.parse({
        'type': 'Point',
        'coordinates': [127.0, 37.5],
      });
      expect(point.longitude, 127.0);
      expect(point.latitude, 37.5);
    });

    test('tryParse returns null for null input', () {
      expect(GeoPoint.tryParse(null), isNull);
    });

    test('tryParse returns null for unrecognized string', () {
      expect(GeoPoint.tryParse('not-a-geometry'), isNull);
    });

    test('parse throws FormatException for unrecognized input', () {
      expect(() => GeoPoint.parse('garbage'), throwsFormatException);
    });

    test('parse throws for non-Point WKB geometry type (e.g. LineString=2)',
        () {
      // type=2 (LineString), SRID 플래그 포함, 좌표 페이로드는 그대로 재사용.
      const lineStringHex =
          '0102000020e6100000e36f7b82c4c15f40287d21e4bcbf4240';
      expect(() => GeoPoint.parse(lineStringHex), throwsFormatException);
    });
  });
}
