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

  /// 특정 상대가 해당 그룹에서 지금 위치 공유를 일시중지 중인지 조회한다.
  ///
  /// `location_share_settings`는 본인 행만 직접 SELECT할 수 있어(RLS) 상대의
  /// on/off 여부는 원천적으로 알 수 없지만, "일시중지 중인지"만은
  /// `is_location_paused` RPC(100002 마이그레이션에서 `authenticated`에게
  /// 이미 grant됨)로 안전하게 물어볼 수 있다 — 반환값 해석(Din UX 리뷰 P0-6,
  /// Plexa 2026-08-24 정정):
  /// - `true`: 실제로 일시중지 중임을 구체적으로 알 수 있는 케이스.
  /// - `false`: 설정 행은 있지만(off 등) 일시중지는 아닌 경우.
  /// - `null`: 설정 행 자체가 없는(한 번도 설정 안 함) 경우.
  ///
  /// `false`와 `null`은 서로 다른 의미이지만(전자는 "명시적으로 껐음", 후자는
  /// "미설정") **호출부에서 절대 다르게 표시해서는 안 된다.** 이 둘을 구분해
  /// 보여주면 상대가 감추고 싶어하는 "off 여부" 자체를 그대로 노출하는
  /// 오라클이 되기 때문이다 — "구분이 안 돼서"가 아니라 "구분되지만 보여주면
  /// 안 돼서" 하나로 합친다. 판단 기준은 오직 `== true`인지 아닌지 하나뿐이다.
  Future<bool?> isLocationPaused(String peerId, String groupId) async {
    final result = await _client.rpc(
      'is_location_paused',
      params: {'p_owner_id': peerId, 'p_relationship_group_id': groupId},
    );
    return result as bool?;
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
