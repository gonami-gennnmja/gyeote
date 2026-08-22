import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'models/location_share_setting.dart';
import 'models/peer_location.dart';

/// 위치 공유 관련 Supabase 접근을 감싸는 repository.
///
/// `relationship_repository.dart`와 동일한 원칙을 따른다:
/// - 조회는 `.select()`로 직접 접근(RLS가 필터링, 단 `location_share_settings`는
///   본인 행만 보이므로 fetch는 사실상 "내 설정"에만 쓸 수 있다).
/// - 쓰기(위치 핑 전송, 공유 모드 변경)는 전부 `.rpc(...)`로만 수행한다.
/// - 상대 위치 스냅샷(`get_peer_locations`)도 RPC이지만 실제로는 조회다 —
///   서버가 SECURITY DEFINER가 아닌 INVOKER 함수로 정의해 RLS를 그대로
///   태우면서 approx 좌표만 반올림하기 위해 RPC 형태를 쓴 것 (마이그레이션
///   주석 참고).
class LocationRepository {
  LocationRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// 내 위치 핑을 서버에 업서트한다.
  ///
  /// 가정(assumption): `p_location` 파라미터(PostGIS geography)는 Supabase
  /// PostgREST가 EWKT 문자열(`SRID=4326;POINT(lng lat)`)을 받아 지오그래피로
  /// 캐스팅하는 표준 방식을 사용한다고 가정한다. 이는 geography의 입력 함수
  /// (`geography_in`)가 EWKT를 그대로 파싱할 수 있기 때문이며, Supabase 커뮤니티
  /// 예제에서도 흔히 쓰이는 방식이다. 실제 프로젝트에 연결했을 때
  /// `invalid input syntax` 류의 에러가 나면 이 형식부터 의심할 것.
  ///
  /// 반환값: 실제로 저장에 성공하면 true, "모든 그룹에서 공유 OFF"라 서버가
  /// 조용히 거부한 경우 false(에러 다이얼로그 없이 무시해야 하므로 예외를
  /// 던지지 않고 상태로만 알려준다). 그 외 에러는 그대로 rethrow한다.
  Future<bool> upsertLocationPing({
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? batteryLevel,
    bool? isCharging,
    String? movementState,
    DateTime? capturedAt,
  }) async {
    final wkt = 'SRID=4326;POINT($longitude $latitude)';

    try {
      await _client.rpc(
        'upsert_location_ping',
        params: {
          'p_location': wkt,
          'p_accuracy_m': accuracyM,
          'p_battery_level': batteryLevel,
          'p_is_charging': isCharging,
          'p_movement_state': movementState,
          'p_captured_at': (capturedAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
        },
      );
      return true;
    } on PostgrestException catch (e) {
      if (_isAllSharesOffError(e)) {
        // 사용자가 모든 그룹에서 위치 공유를 의도적으로 꺼둔 상태.
        // 에러가 아니라 정상적인 "보낼 필요 없음" 상태이므로 조용히 무시한다.
        return false;
      }
      rethrow;
    }
  }

  bool _isAllSharesOffError(PostgrestException e) {
    // upsert_location_ping()의 raise exception 메시지
    // ('location sharing is off for all groups; ...')를 그대로 매칭한다.
    // 백엔드가 별도 에러 코드를 정의하지 않았으므로(plain raise exception),
    // 메시지 문자열 매칭이 현재로선 유일한 판별 수단이다. 향후 백엔드가
    // 전용 에러 코드/detail을 추가하면 이 매칭을 더 견고하게 바꿀 것.
    final message = e.message.toLowerCase();
    return message.contains('location sharing is off');
  }

  /// 특정 관계 그룹에서 상대들의 최신 위치 스냅샷.
  Future<List<PeerLocation>> getPeerLocations(String relationshipGroupId) async {
    final rows = await _client.rpc(
      'get_peer_locations',
      params: {'p_relationship_group_id': relationshipGroupId},
    );

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PeerLocation.fromJson)
        .toList();
  }

  /// 그룹별 위치 공유 모드 변경 (+ 선택적으로 N분간 일시중지).
  ///
  /// 가정/해석 메모: 과제 요구사항의 "N분만 임시 공유" 문구는 문자 그대로
  /// 읽으면 "지금부터 N분만 켜기"처럼 들리지만, 백엔드 스키마 주석
  /// (20260820090008/090011)을 보면 `paused_until`은 오직 "이미 켜진 공유를
  /// N분간 임시로 숨기기(일시중지)"만 표현할 수 있다 — mode가 off일 때
  /// pause를 거는 것은 의미가 없고, mode가 precise/approx일 때 pause를 걸면
  /// 오히려 그 시간 동안 안 보이게 된다. 따라서 이 repository/화면은
  /// "N분간 일시중지"로 해석해 구현한다(코드/화면 문구에도 명시).
  Future<LocationShareSetting> setShareMode({
    required String relationshipGroupId,
    required String mode,
    int? pauseMinutes,
  }) async {
    final row = await _client.rpc(
      'set_location_share_mode',
      params: {
        'p_relationship_group_id': relationshipGroupId,
        'p_mode': mode,
        'p_pause_minutes': pauseMinutes,
      },
    );

    return LocationShareSetting.fromJson(row as Map<String, dynamic>);
  }

  /// 내 모든 그룹의 공유 설정. `location_share_settings`는 본인 행만 SELECT
  /// 가능하므로 별도 group 필터 없이 전체를 가져와 화면에서 그룹별로 매핑한다.
  /// 아직 한 번도 설정하지 않은 그룹은 행 자체가 없다 (기본값 'off'로 취급).
  Future<List<LocationShareSetting>> fetchMyShareSettings() async {
    final uid = currentUserId;
    if (uid == null) return const [];

    final rows = await _client
        .from('location_share_settings')
        .select()
        .eq('user_id', uid);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(LocationShareSetting.fromJson)
        .toList();
  }
}
