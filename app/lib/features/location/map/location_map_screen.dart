import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../relationships/data/relationship_repository.dart';
import '../data/location_repository.dart';
import '../data/models/geo_point.dart';
import '../data/models/peer_location.dart';
import '../hidden_peers.dart';

/// 특정 관계 그룹의 상대 위치를 지도에 표시하는 화면.
///
/// "스냅샷 + 델타" 패턴(과제 요구사항):
///  1) 진입 시 `get_peer_locations`로 초기 스냅샷을 불러온다.
///  2) Private 채널(`relationship:{group_id}:location`, `private: true`)을
///     구독해 이후 변경분만 델타로 반영한다.
///  3) 브로드캐스트는 유실될 수 있으므로(앱이 백그라운드였거나 재연결 중이면
///     놓칠 수 있음), 앱이 foreground로 돌아올 때(`AppLifecycleState.resumed`)
///     마다 스냅샷을 다시 불러오고 채널도 재구독한다.
///
/// 가정(assumption, 검증 필요): `opts: RealtimeChannelConfig(private: true)`
/// API는 supabase_flutter의 비교적 최근 버전(Realtime Authorization/브로드캐스트
/// 인가 지원 이후)에서 제공된다. `pubspec.yaml`에서 supabase_flutter를
/// ^2.8.0으로 올려둔 이유가 이것이다 — 실제 `flutter pub get` 시 이 API가
/// 없다는 에러가 나면 패키지 버전을 더 올려야 한다.
class LocationMapScreen extends StatefulWidget {
  const LocationMapScreen({
    required this.groupId,
    required this.groupName,
    this.repository,
    this.relationshipRepository,
    super.key,
  });

  final String groupId;
  final String groupName;

  /// 테스트에서 가짜 repository를 주입하기 위한 선택적 파라미터. 프로덕션
  /// 호출부는 그대로 두면 되고(전달하지 않으면 null), null이면 지금까지와
  /// 동일하게 이 화면이 실제 repository를 직접 생성해 쓴다 — 위젯 테스트가
  /// `pumpWidget` 시점에 실제 Supabase 초기화 없이도 진입할 수 있게 하는
  /// 용도일 뿐, 프로덕션 동작을 바꾸지 않는다.
  final LocationRepository? repository;
  final RelationshipRepository? relationshipRepository;

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen>
    with WidgetsBindingObserver {
  late final _repository = widget.repository ?? LocationRepository();
  late final _relationshipRepository =
      widget.relationshipRepository ?? RelationshipRepository();

  GoogleMapController? _mapController;
  RealtimeChannel? _channel;

  /// 피어가 브로드캐스트를 멈추면(상대가 앱을 껐거나 네트워크가 끊긴 상황 —
  /// 위치가 "오래되는" 바로 그 경우) `_peers`는 그대로라 setState가 다시
  /// 불리지 않고, `PeerLocation.isStale()`이 true로 바뀌어도 마커/칩이 흐려지지
  /// 않는다(Rena 리뷰 P1). 화면이 살아 있는 동안 1분마다 빈 setState를 돌려
  /// 신선도 판정을 다시 그리게 한다.
  Timer? _staleTicker;

  Map<String, PeerLocation> _peers = {};
  List<HiddenPeer> _hiddenPeers = [];
  bool _isLoading = true;
  Object? _error;

  String? get _currentUserId => _repository.currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _staleTicker = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
    _refresh();
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 브로드캐스트 유실 가능성(백그라운드/재연결) 대비: 포그라운드 복귀 시
      // 스냅샷 재조회 + 채널 재구독.
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final peers = await _repository.getPeerLocations(widget.groupId);
      if (!mounted) return;
      setState(() {
        _peers = {for (final p in peers) p.userId: p};
        _error = null;
        _isLoading = false;
      });
      unawaited(_refreshHiddenPeers());
    } catch (e, stackTrace) {
      // 원본 예외는 로그에만 남기고 사용자에게는 정제된 문구만 보여준다
      // (Din UX 리뷰 P0-4 — 원본 예외 노출은 UX 문제이자 정보 노출 문제).
      developer.log(
        '위치 스냅샷 조회 실패',
        name: 'LocationMapScreen',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }

    try {
      _subscribeRealtime();
    } catch (e, stackTrace) {
      // 구독 실패가 스냅샷 조회 성공까지 덮어써서는 안 된다 — 이미 받아온
      // 스냅샷으로 지도 본체는 정상 표시 가능한 상황인데, 구독 예외가 위
      // try/catch 밖에서 그대로 터지면 _refresh() 전체가 깨져 그 스냅샷마저
      // 화면에 못 그리게 된다(Rena 재리뷰 지적). 숨은 멤버 조회와 동일하게
      // 별도로 감싸고 로그만 남긴다.
      developer.log(
        'realtime 채널 구독 실패',
        name: 'LocationMapScreen',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// `get_peer_locations`는 이 그룹에서 off/미설정/일시중지 중인 상대를
  /// 결과에서 완전히 제외한다(100002 마이그레이션). 그런 상대가 화면에서
  /// 아무 설명 없이 사라지지 않도록, "그룹 로스터엔 있는데 위치 결과엔
  /// 없는" 상대를 따로 골라 별도 섹션에 표시한다(Din UX 리뷰 P0-6).
  ///
  /// 실제 "판단"(누가 숨은 멤버인지, `is_location_paused`의 `false`/`null`을
  /// 절대 구분하지 않는다는 규칙 포함)은 화면 밖 순수 함수인
  /// `hidden_peers.dart`의 `selectHiddenCandidates`/`buildHiddenPeers`로
  /// 뽑아뒀다(`ShareStatusSummary.compute()`와 같은 방식) — 위젯을 띄우지
  /// 않고도 그 판단만 단위 테스트할 수 있게 하기 위해서다. 이 메서드는 비동기
  /// 조회(로스터 fetch, `isLocationPaused` N+1 호출)를 오케스트레이션해서 그
  /// 순수 함수들에 데이터를 넣어주는 역할만 한다. 이 화면의 핵심 지도/칩
  /// 표시와는 별개 기능이므로 실패해도 지도 표시 자체를 에러로 만들지 않고
  /// 로그만 남긴다.
  Future<void> _refreshHiddenPeers() async {
    try {
      final roster = await _relationshipRepository.fetchGroupMembers(
        widget.groupId,
      );
      final candidates = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: _peers.keys,
        currentUserId: _currentUserId,
      );

      final pausedFlags = await Future.wait(
        candidates.map(
          (m) => _repository.isLocationPaused(m.userId, widget.groupId),
        ),
      );
      final pausedByUserId = {
        for (var i = 0; i < candidates.length; i++)
          candidates[i].userId: pausedFlags[i],
      };

      if (!mounted) return;
      setState(() {
        _hiddenPeers = buildHiddenPeers(
          candidates: candidates,
          pausedByUserId: pausedByUserId,
        );
      });
    } catch (e, stackTrace) {
      developer.log(
        '위치가 보이지 않는 멤버 상태 조회 실패',
        name: 'LocationMapScreen',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _subscribeRealtime() {
    _unsubscribeRealtime();

    final client = SupabaseService.client;
    final topic = 'relationship:${widget.groupId}:location';

    // private: true가 반드시 필요하다 — false로 두면 서버의 Realtime
    // Authorization(RLS)이 적용되지 않아 그룹 비멤버도 구독할 수 있게 된다
    // (20260820090012_location_realtime.sql 참고).
    final channel = client.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true),
    );

    channel
        .onBroadcast(
          event: 'location_update',
          callback: (payload) => _onRealtimeUpdate(payload),
        )
        .subscribe();

    _channel = channel;
  }

  void _unsubscribeRealtime() {
    final channel = _channel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
      _channel = null;
    }
  }

  void _onRealtimeUpdate(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    if (userId == null || userId == _currentUserId) return;

    final lat = (payload['latitude'] as num?)?.toDouble();
    final lng = (payload['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final capturedAtRaw = payload['captured_at'] as String?;
    final capturedAt = capturedAtRaw != null
        ? DateTime.parse(capturedAtRaw)
        : DateTime.now().toUtc();

    // 브로드캐스트 payload에는 서버 `received_at`이 포함되지 않는다(과제
    // 명세의 payload 필드 목록 참고). 신선도는 "이 클라이언트가 언제 이
    // 갱신을 받았는가"를 대리 지표로 써서 `DateTime.now()`를 received_at으로
    // 채워 넣는다 — 스냅샷(get_peer_locations)의 진짜 서버 received_at과
    // 의미가 완전히 같지는 않다는 점을 인지하고 있어야 한다(가정).
    final receivedAt = DateTime.now().toUtc();
    final mode = payload['mode'] as String? ?? _peers[userId]?.mode ?? 'precise';

    final existing = _peers[userId];
    final updated = PeerLocation(
      userId: userId,
      nickname: existing?.nickname ?? '알 수 없음',
      position: GeoPoint(latitude: lat, longitude: lng),
      accuracyM: (payload['accuracy_m'] as num?)?.toDouble(),
      batteryLevel: payload['battery_level'] as int?,
      isCharging: payload['is_charging'] as bool?,
      movementState: payload['movement_state'] as String?,
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      mode: mode,
    );

    if (!mounted) return;
    setState(() => _peers = {..._peers, userId: updated});
  }

  Set<Marker> _buildMarkers() => buildPeerMarkers(_peers.values);

  Set<Circle> _buildApproxCircles() {
    // mode='approx'인 상대는 좌표 자체가 이미 서버에서 ~100m 격자로
    // 반올림되어 있으므로, 지도에서도 "정확한 지점"이 아니라 "이 근방"임을
    // 시각적으로 구분해준다.
    return _peers.values.where((p) => p.isApprox).map((peer) {
      final center = LatLng(peer.position.latitude, peer.position.longitude);
      return Circle(
        circleId: CircleId('${peer.userId}_approx'),
        center: center,
        radius: 150,
        // 가정: 프로젝트 sdk 하한(Flutter >=3.19.0)과의 호환을 위해 최신
        // `Color.withValues` 대신 `withOpacity`를 사용한다(구버전 SDK에서
        // `withValues`가 없을 수 있음).
        fillColor: Colors.orange.withOpacity(0.15),
        strokeColor: Colors.orange,
        strokeWidth: 1,
      );
    }).toSet();
  }

  CameraPosition _initialCamera() {
    if (_peers.isNotEmpty) {
      final first = _peers.values.first;
      return CameraPosition(
        target: LatLng(first.position.latitude, first.position.longitude),
        zoom: 13,
      );
    }
    // 기본값: 서울시청 부근 (아직 아무도 위치를 공유하지 않은 경우).
    return const CameraPosition(target: LatLng(37.5665, 126.9780), zoom: 11);
  }

  void _focusOn(PeerLocation peer) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(peer.position.latitude, peer.position.longitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peers = _peers.values.toList()
      ..sort((a, b) => a.nickname.compareTo(b.nickname));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} 위치'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _error != null
          ? _ErrorState(error: _error!, onRetry: _refresh)
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: _initialCamera(),
                        onMapCreated: (controller) => _mapController = controller,
                        markers: _buildMarkers(),
                        circles: _buildApproxCircles(),
                        myLocationButtonEnabled: false,
                      ),
                      if (_isLoading)
                        const Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_isLoading && peers.isEmpty)
                        const Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                '아직 공유된 위치가 없어요. 상대가 위치 공유를 켜면 여기에 표시돼요.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (peers.isNotEmpty)
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) =>
                          _PeerSummaryChip(peer: peers[index], onTap: () => _focusOn(peers[index])),
                    ),
                  ),
                if (_hiddenPeers.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      '지금 위치가 보이지 않는 멤버',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  SizedBox(
                    // 84 = 텍스트 두 줄(닉네임 1줄 + 상태 문구 최대 2줄) +
                    // Container 패딩이 실제로 필요로 하는 높이보다 여유를 둔
                    // 값이다. 이전에는 72였는데, 이 화면이 위젯 테스트로 실제
                    // 렌더링된 게 이번이 처음이라 그때 2px RenderFlex overflow가
                    // 드러났다(Tom 발견) — 폰트 배율(접근성 텍스트 크기 확대)에서도
                    // 다시 넘치지 않도록 여유를 넉넉히 잡았다.
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: _hiddenPeers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) =>
                          _HiddenPeerChip(hidden: _hiddenPeers[index]),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// `_peers`의 각 피어를 지도 마커로 변환한다. 위젯/플랫폼을 띄우지 않고도
/// 단위 테스트할 수 있도록 화면 밖 순수 함수로 뒀다(`hidden_peers.dart`,
/// `shareModeDescription`과 같은 방식). `now`를 주입하면 그대로
/// `PeerLocation.isStale`로 전달돼, "상대가 앱을 껐고 그 뒤로 시간만 흐른"
/// 상황(receivedAt은 고정, now만 진행)을 테스트에서 재현할 수 있다.
Set<Marker> buildPeerMarkers(Iterable<PeerLocation> peers, {DateTime? now}) {
  return peers.map((peer) {
    return Marker(
      markerId: MarkerId(peer.userId),
      position: LatLng(peer.position.latitude, peer.position.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        peer.isApprox ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
      ),
      // 오래된 위치도 방금 위치와 똑같이 진하게 보이면 "지금 여기 있다"고
      // 오해하기 쉽다(Din UX 리뷰 P1-3). 신선도 판단은 PeerLocation.isStale()
      // 에 있고, 여기서는 그 결과로 alpha만 낮춘다.
      alpha: peer.isStale(now: now) ? PeerLocation.staleOpacity : 1.0,
      infoWindow: InfoWindow(
        title: peer.nickname,
        snippet: '${peer.freshnessLabel()}'
            '${peer.isApprox ? ' · 대략적 위치' : ''}',
      ),
    );
  }).toSet();
}

class _HiddenPeerChip extends StatelessWidget {
  const _HiddenPeerChip({required this.hidden});

  final HiddenPeer hidden;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    // hidden.isPaused를 여기서 직접 == true로 비교하지 않는다 — false/null을
    // 구분하지 않는다는 규칙은 HiddenPeer.showPausedBadge(순수 계층, 테스트로
    // 검증됨)에 있고, 이 위젯은 그 결과만 그린다.
    final showPausedBadge = hidden.showPausedBadge;
    final icon =
        showPausedBadge ? Icons.pause_circle_outline : Icons.visibility_off_outlined;
    final label =
        showPausedBadge ? '일시중지 중 · 곧 다시 보일 수 있어요' : '지금은 위치가 보이지 않아요';

    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hidden.member.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _MapErrorKind { network, authExpired, generic }

/// 원본 예외를 종류별로 분류한다 — 판별 우선순위는 네트워크 끊김 -> 인증 만료
/// -> 그 외 순서다. 네트워크가 끊긴 상태에서 인증도 만료돼 있을 수 있는데,
/// 이 경우 "인터넷부터 확인하라"는 메시지가 사용자에게 더 실행 가능하기
/// 때문이다(Din UX 리뷰 P0-4 최종 카피 확정, 2026-08-23).
_MapErrorKind _classifyError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return _MapErrorKind.network;
  }
  if (error is AuthException) return _MapErrorKind.authExpired;
  if (error is PostgrestException &&
      (error.code == 'PGRST301' || error.code == '401')) {
    return _MapErrorKind.authExpired;
  }
  return _MapErrorKind.generic;
}

/// 위치 스냅샷 조회 실패 시 보여주는 화면.
///
/// 원본 예외(`Object`)를 절대 화면 문자열에 보간하지 않는다 — 스택트레이스성
/// 텍스트나 영어 예외 메시지가 그대로 노출되는 것을 막기 위함(Din UX 리뷰
/// P0-4). 세 케이스 모두 고정된 한글 문구만 사용하고 `e.message`/`e.toString()`
/// 등 원본 텍스트는 절대 화면에 넣지 않는다 — 이 화면이 호출하는
/// `get_peer_locations`는 `raise exception`이 없는 순수 SELECT라서, 여기 담길
/// 수 있는 `PostgrestException.message`는 우리가 정의한 안전한 매핑 대상이
/// 아니라 항상 Postgres/PostgREST 인프라 레벨의 영어 원문뿐이기 때문이다
/// (Din UX 리뷰 "서버 예외 메시지 전수 조사", 2026-08-23 정정). 원본 예외는
/// 호출 쪽(`_refresh`)에서 이미 로그로 남겼다.
///
/// `get_peer_locations`는 호출자가 그룹 멤버가 아니어도 예외 없이 빈 결과를
/// 반환하도록 이미 수정돼 있으므로(HIGH-2,
/// `20260823100002_fix_location_spoofing_and_scope_bypass.sql`), "그룹 접근
/// 권한 없음"은 별도 에러 케이스로 다루지 않는다 — 그 경우는 기존 빈 상태
/// 문구로 자연스럽게 처리된다.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  Future<void> _reauth(BuildContext context) async {
    await AuthRepository().signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = _classifyError(error);

    final IconData icon;
    final String message;
    switch (kind) {
      case _MapErrorKind.network:
        icon = Icons.wifi_off;
        message = '네트워크에 연결되어 있지 않아요.\nWi-Fi나 데이터 연결을 확인하고 다시 시도해주세요.';
        break;
      case _MapErrorKind.authExpired:
        icon = Icons.lock_outline;
        message = '로그인이 만료됐어요.\n다시 로그인하면 위치를 볼 수 있어요.';
        break;
      case _MapErrorKind.generic:
        icon = Icons.error_outline;
        message = '위치 정보를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: kind == _MapErrorKind.authExpired
                  ? () => _reauth(context)
                  : onRetry,
              child: Text(kind == _MapErrorKind.authExpired ? '다시 로그인' : '다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerSummaryChip extends StatelessWidget {
  const _PeerSummaryChip({required this.peer, required this.onTap});

  final PeerLocation peer;
  final VoidCallback onTap;

  IconData get _batteryIcon {
    if (peer.isCharging == true) return Icons.battery_charging_full;
    final level = peer.batteryLevel;
    if (level == null) return Icons.battery_unknown;
    if (level >= 95) return Icons.battery_full;
    if (level >= 80) return Icons.battery_6_bar;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 35) return Icons.battery_3_bar;
    if (level >= 20) return Icons.battery_2_bar;
    if (level >= 5) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  IconData get _movementIcon {
    switch (peer.movementState) {
      case 'moving':
        return Icons.directions_car;
      case 'walking':
        return Icons.directions_walk;
      case 'stationary':
        return Icons.person_pin_circle;
      default:
        return Icons.person_pin_circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isStale = peer.isStale();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          // 오래된 위치는 배경을 톤다운한다(Din UX 리뷰 P1-3) — 지도를
          // 훑어볼 때 텍스트를 일일이 읽지 않아도 방금 위치와 구분되게 하려는
          // 것. 반투명(withOpacity)으로 두면 뒤 지도 타일이 비쳐 대비가
          // 떨어지므로(Rena 리뷰 P2), 같은 색을 surface 위에 미리 합성해
          // 불투명색으로 만든다. 톤다운 정도(staleOpacity)는 마커 alpha와
          // 공유한다.
          color: isStale
              ? Color.alphaBlend(
                  colorScheme.surfaceContainerHighest
                      .withOpacity(PeerLocation.staleOpacity),
                  colorScheme.surface,
                )
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(_movementIcon, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    peer.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (peer.isApprox)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.blur_on, size: 14, color: Colors.orange),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(_batteryIcon, size: 16),
                const SizedBox(width: 4),
                Text(
                  peer.batteryLevel != null ? '${peer.batteryLevel}%' : '-',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (isStale) ...[
                  Icon(Icons.history, size: 12, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                ],
                Text(
                  peer.freshnessLabel(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isStale ? colorScheme.onSurfaceVariant : null,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
