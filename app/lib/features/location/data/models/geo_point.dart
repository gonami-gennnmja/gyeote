import 'dart:typed_data';

/// PostGIS `geography(Point, 4326)` 값을 위도/경도로 파싱하는 헬퍼.
///
/// 가정(assumption, 반드시 실서버 연동 시 검증 필요):
/// `get_peer_locations()` RPC는 `location` 컬럼을 `extensions.geography`
/// 타입 그대로 반환한다(20260820090011_location_functions.sql 참고). PostgREST가
/// 이를 JSON으로 직렬화할 때는 Postgres의 `to_json`이 해당 타입의 텍스트 출력
/// 함수(`geography_out`)를 그대로 문자열로 감싸는데, PostGIS의 기본 텍스트
/// 출력은 사람이 읽는 WKT가 아니라 **EWKB(hex 문자열)**이다
/// (예: `"0101000020E6100000...”`, 접두 `0101000020`은 리틀엔디안 +
/// SRID-포함 Point 타입 플래그).
///
/// 이 클래스는 실제로 받을 가능성이 있는 세 가지 형태를 모두 방어적으로
/// 파싱한다:
///   1) EWKB/WKB hex 문자열 (가장 유력한 기본 케이스)
///   2) WKT/EWKT 문자열, 예: `"POINT(127.0 37.5)"`, `"SRID=4326;POINT(...)"`
///   3) GeoJSON 형태의 Map, 예: `{"type":"Point","coordinates":[lng,lat]}`
///      (PostgREST 설정에 따라 PostGIS의 `postgis_jsonb` 변환이 적용되어 있거나
///      뷰/함수에서 `ST_AsGeoJSON`을 쓰는 경우 이 형태로 올 수 있다)
///
/// 실서버(QA) 라운드에서 실제 응답 payload를 한 번 확인해, 셋 중 어느
/// 경로를 타는지 로그로 남기고 불필요한 분기를 정리할 것을 권장한다.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  static GeoPoint? tryParse(Object? value) {
    if (value == null) return null;

    if (value is Map) {
      return _fromGeoJson(value);
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;

      if (_looksLikeHex(trimmed)) {
        final fromHex = _fromEwkbHex(trimmed);
        if (fromHex != null) return fromHex;
      }

      return _fromWkt(trimmed);
    }

    return null;
  }

  /// 필수로 위치가 있어야 하는 곳(예: `get_peer_locations` 행)에서 사용.
  /// 파싱 실패 시 예외를 던져 "조용히 잘못된 좌표를 표시"하는 상황을 막는다.
  static GeoPoint parse(Object? value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('알 수 없는 geography 형식입니다: $value');
    }
    return parsed;
  }

  static bool _looksLikeHex(String s) {
    if (s.length < 18 || s.length.isOdd) return false;
    final hexOnly = RegExp(r'^[0-9a-fA-F]+$');
    return hexOnly.hasMatch(s);
  }

  static GeoPoint? _fromGeoJson(Map value) {
    final coords = value['coordinates'];
    if (coords is List && coords.length >= 2) {
      final lng = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      return GeoPoint(latitude: lat, longitude: lng);
    }
    return null;
  }

  static GeoPoint? _fromWkt(String s) {
    // "SRID=4326;POINT(127.0 37.5)" 또는 "POINT(127.0 37.5)" 모두 대응.
    final match = RegExp(
      r'POINT\s*\(\s*([-\d.eE]+)\s+([-\d.eE]+)\s*\)',
      caseSensitive: false,
    ).firstMatch(s);
    if (match == null) return null;

    final lng = double.tryParse(match.group(1)!);
    final lat = double.tryParse(match.group(2)!);
    if (lng == null || lat == null) return null;
    return GeoPoint(latitude: lat, longitude: lng);
  }

  /// 최소한의 EWKB/WKB Point 파서. Z/M 차원이나 SRID 포함 여부 플래그를
  /// 해석해 X(경도)/Y(위도) 8바이트 double 두 개만 읽어낸다.
  static GeoPoint? _fromEwkbHex(String hex) {
    try {
      final bytes = _hexToBytes(hex);
      if (bytes.isEmpty) return null;

      final byteData = ByteData.sublistView(bytes);
      final isLittleEndian = bytes[0] == 1;
      final endian = isLittleEndian ? Endian.little : Endian.big;

      var offset = 1;
      final typeAndFlags = byteData.getUint32(offset, endian);
      offset += 4;

      const wkbZFlag = 0x80000000;
      const wkbMFlag = 0x40000000;
      const wkbSridFlag = 0x20000000;

      final geomType = typeAndFlags & 0xFF; // 1 = Point
      if (geomType != 1) return null;

      if (typeAndFlags & wkbSridFlag != 0) {
        offset += 4; // SRID (사용하지 않음, 4326으로 가정)
      }

      final x = byteData.getFloat64(offset, endian); // longitude
      offset += 8;
      final y = byteData.getFloat64(offset, endian); // latitude

      // Z/M 값은 있더라도 무시(2D 좌표만 필요).
      final _ = typeAndFlags & (wkbZFlag | wkbMFlag);

      return GeoPoint(latitude: y, longitude: x);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  @override
  String toString() => 'GeoPoint(lat: $latitude, lng: $longitude)';
}
