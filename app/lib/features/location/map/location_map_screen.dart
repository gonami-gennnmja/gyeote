import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/location_repository.dart';
import '../data/models/geo_point.dart';
import '../data/models/peer_location.dart';

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
    super.key,
  });

  final String groupId;
  final String groupName;

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen>
    with WidgetsBindingObserver {
  final _repository = LocationRepository();

  GoogleMapController? _mapController;
  RealtimeChannel? _channel;

  Map<String, PeerLocation> _peers = {};
  bool _isLoading = true;
  Object? _error;

  String? get _currentUserId => _repository.currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }

    _subscribeRealtime();
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

  Set<Marker> _buildMarkers() {
    return _peers.values.map((peer) {
      final position = LatLng(peer.position.latitude, peer.position.longitude);
      return Marker(
        markerId: MarkerId(peer.userId),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          peer.isApprox ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(
          title: peer.nickname,
          snippet: '${peer.freshnessLabel()}'
              '${peer.isApprox ? ' · 대략적 위치' : ''}',
        ),
      );
    }).toSet();
  }

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
          ? Center(child: Text('불러오지 못했습니다: $_error'))
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
                                '아직 공유된 위치가 없습니다. 상대가 위치 공유를 켜면 여기에 표시돼요.',
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
              ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                Text(
                  peer.freshnessLabel(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
