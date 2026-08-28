# 위치 공유 기능 UX 검토 (Phase 0~1)

- 작성: Din (Designer)
- 대상: Diana (Frontend Dev) 구현 참고용 — 코드는 수정하지 않음, 카피/구조/우선순위만 정리
- 검토 대상 파일
  - `app/lib/features/location/permission/location_permission_screen.dart`
  - `app/lib/features/location/map/location_map_screen.dart`
  - `app/lib/features/location/settings/share_settings_screen.dart`
  - `app/lib/features/home/presentation/screens/home_screen.dart`
  - `app/lib/features/relationships/presentation/screens/group_detail_screen.dart`
- 참고로 함께 읽은 파일: `location_permission_service.dart`, `location_collector_service.dart`, `models/peer_location.dart`, `models/location_share_setting.dart`

이 기능은 "누구에게 내 위치가 얼마나 정확하게 보이는가"를 사용자가 항상 정확히
알고 있어야 하는 프라이버시 기능이다. 아래 우선순위는 **"현재 상태를 오해할 여지가
있는가"** 를 최우선 기준으로 매겼다. Phase가 사진/버킷리스트로 넘어가도 이 화면들은
그대로 남으므로 버려지는 작업이 아니다.

---

## 요약

| 우선순위 | 개수 | 핵심 |
|---|---|---|
| P0 | 7건 | 실제 공유 상태와 화면에 보이는 상태가 어긋나거나, 서버 원문 메시지가 그대로 노출될 수 있는 항목 |
| P1 | 7건 | 이해도/진입 흐름을 개선하는 항목 |
| P2 | 6건 | 톤/디테일 다듬기 |

---

## P0 — 지금 반영 필요 (오해·프라이버시 리스크)

### P0-1. 공유 설정 화면에 "지금 누구에게 보이는가" 요약이 없다

**파일**: `share_settings_screen.dart`

현재 화면은 상단 "내 위치 수집" 스위치 + 그룹별 카드(off/정밀/대략)로 구성되는데,
실제로 상대방에게 위치가 보이려면 **① 수집 스위치 ON, ② 해당 그룹 모드가
off가 아님, ③ 일시중지 중이 아님** 세 조건이 동시에 만족해야 한다. 사용자는
이 세 조건을 화면 여기저기서 직접 조합해서 판단해야 하고, 특히 수집 스위치가
꺼져 있으면 그룹 카드가 "정밀"로 선택되어 있어도 실제로는 아무에게도 보이지
않는데 화면상으로는 "정밀 공유 중"처럼 보인다. 반대로 착각하면 "꺼져 있으니
안전하다"고 믿고 있다가 실제로는 노출되는 경우도 생길 수 있다.

**개선안**: 화면 최상단, 수집 스위치 카드 바로 아래에 현재 실제 공유 상태를
한 줄로 요약하는 배너를 추가한다.

- 수집 OFF일 때: `"현재 위치 공유가 꺼져 있어요. 아무에게도 보이지 않습니다."` (중립 톤 아이콘)
- 수집 ON, 공유 중인 그룹이 1개 이상: `"OO, OO에게 위치가 공유되고 있어요."` (그룹 표시명 나열, 3개 초과 시 "외 N곳")
- 수집 ON인데 모든 그룹이 off: `"위치 수집은 켜져 있지만, 아직 공유 중인 그룹이 없어요. 아래에서 그룹을 선택해주세요."`
- 일부 그룹이 일시중지 중이면 요약 문장에 `"(OO는 일시중지 중)"` 병기

이 배너는 그룹 카드들의 상태 변화(모드 변경/일시중지/재개, 수집 토글)에
반응해 즉시 갱신되어야 한다.

**검증(Din, 2026-08-24)**: `share_status_summary.dart`의
`ShareStatusSummary.compute()` 코드를 직접 추적해 4가지 케이스를 모두
확인했다 — 특히 "수집 ON + 모든 그룹 off/미설정" 조합이 `sharingGroups`가
비어 세 번째 케이스(collectingOnly)로 정확히 분기됨을 확인. 일부만
일시중지인 조합도 병기 규칙대로 동작. 의도대로 구현됨.

### P0-2. 그룹 카드가 "수집이 꺼져 있어 실제로는 공유되지 않음"을 표시하지 않는다

**파일**: `share_settings_screen.dart` — `_GroupShareCard`

`_toggleCollector(false)`로 수집을 끈 상태에서도 그룹 카드의 SegmentedButton은
이전에 선택했던 "정밀"/"대략" 상태를 그대로 보여준다. P0-1의 전역 배너로 상단
요약은 해결되지만, 카드 자체에도 "선택은 정밀이지만 지금은 전송되지 않음"을
알려야 사용자가 특정 그룹만 봤을 때 헷갈리지 않는다.

**개선안**: 수집이 꺼진 동안 각 `_GroupShareCard` 상단에 작은 보조 문구를 추가한다.

```
"⚠ 위치 수집이 꺼져 있어 이 설정은 적용되지 않아요."
```

SegmentedButton 자체는 비활성화(disabled)하지 않는다 — 사용자가 미리 모드를
정해둘 수 있어야 하므로, 다만 시각적으로 톤다운(예: opacity 0.6)해 "지금 당장
발효되는 설정이 아님"을 드러낸다.

**검증(Din, 2026-08-24)**: 경고 문구·`Opacity(opacity: collectorRunning ? 1.0 : 0.6)`
모두 문구·수치까지 그대로 구현됨. SegmentedButton은 비활성화하지 않고 톤다운만
한 것도 의도대로.

### P0-3. 권한 프라이밍 화면이 "포그라운드에서만 수집됨"을 설명하지 않는다

**파일**: `location_permission_screen.dart`, 배경: `location_permission_service.dart`
(`requestWhileInUse`만 요청, `grantedAlways` 요청 UI 없음), `location_collector_service.dart`
(수집기가 앱이 살아있을 때만 동작).

이 앱은 이번 라운드에서 "앱 사용 중" 권한만 요청하고 "항상 허용"은 요청하지
않는다. 즉 **앱을 완전히 종료하거나 오래 백그라운드에 두면 내 위치가 상대에게
갱신되지 않는다.** 그런데 프라이밍 화면 안내 문구("가족·연인·친구와 실시간
위치를 공유하려면...")는 이 제약을 전혀 언급하지 않는다. 커플/가족 위치공유
앱 사용자는 통상 "앱을 안 켜도 항상 보인다"를 기대하기 때문에, 이 기대와
실제 동작의 격차가 신뢰 문제로 이어질 수 있다. (마지막 위치가 오래됐을 때
왜 그런지 사용자가 이유를 모르면 "앱이 고장났다"고 오해하게 된다.)

**개선안**: 프라이밍 화면의 안내 목록에 항목 하나를 추가한다.

```
• 지금은 앱이 켜져 있을 때만 위치가 전달돼요. 앱을 완전히 끄면
  위치 공유가 잠시 멈춰요. (백그라운드 공유는 다음 업데이트 예정)
```

권한 요청 자체는 이번 라운드 범위대로 `requestWhileInUse()`만 유지하되(범위
변경 요청 아님), **사용자에게 그 사실을 미리 알리는 카피만** 추가하는 것이
목표다. "항상 허용" 권한을 실제로 요청하게 되는 다음 라운드가 오면 이 문구를
제거하고 always 권한 온보딩으로 교체한다.

**검증(Din, 2026-08-24)**: 안내 문구가 글자 그대로 추가됨. 의도대로 구현됨.

### P0-4. 지도 화면의 에러 상태가 원본 예외를 그대로 노출한다

**파일**: `location_map_screen.dart:242`

```dart
Center(child: Text('불러오지 못했습니다: $_error'))
```

`share_settings_screen.dart`의 다른 에러 처리(`PostgrestException` 분기 후
일반 메시지로 폴백)와 달리, 지도 화면은 Dart 예외 객체(`Object`)를 문자열
보간해 그대로 사용자에게 보여준다. 스택트레이스성 텍스트나 영어 예외 메시지가
그대로 노출될 수 있고, 재시도 동선도 없다.

**개선안**:

```
아이콘(예: Icons.wifi_off 또는 Icons.error_outline) +
"위치 정보를 불러오지 못했어요.\n네트워크를 확인하고 다시 시도해주세요." +
FilledButton("다시 시도") → onPressed: _refresh
```

`PostgrestException`이면 `e.message`를 보조 텍스트로 표시하고, 그 외에는
위 고정 문구만 사용한다(원본 예외 텍스트를 사용자에게 노출하지 않는다).

#### P0-4 최종 카피 확정 (Plexa 요청, 2026-08-23 추가)

`_refresh()`의 catch 블록에서 에러 종류에 따라 아래 3가지로 분기한다.
우선순위는 위(네트워크 끊김)에서 아래(그 외 일반 실패) 순으로 판별한다 —
네트워크가 끊긴 상태에서 인증도 만료돼 있을 수 있는데, 이 경우 사용자에게는
"인터넷부터 확인하라"는 메시지가 더 실행 가능하다.

**① 네트워크 끊김**
판별: `SocketException`(dart:io) 또는 `TimeoutException`(dart:async) —
프로젝트에 이미 연결성 체크 유틸이 있다면 그것을 우선 사용해도 무방.

```
아이콘: Icons.wifi_off
본문: "네트워크에 연결되어 있지 않아요.\nWi-Fi나 데이터 연결을 확인하고 다시 시도해주세요."
버튼: FilledButton("다시 시도") → onPressed: _refresh
```

**② 인증 세션 만료 ("권한 없음")**
판별: `AuthException`(supabase_flutter) 또는 401/세션 관련 코드의
`PostgrestException`. 참고: `get_peer_locations`는 호출자가 그룹 멤버가
아니어도 예외 없이 **빈 결과**를 반환하도록 이미 수정돼 있으므로(HIGH-2
수정, `20260823100002_fix_location_spoofing_and_scope_bypass.sql`), "그룹
비멤버라 접근 거부"라는 별도 에러 케이스는 만들 필요 없다 — 그 경우는 이미
있는 빈 상태 문구("아직 공유된 위치가 없습니다...")로 자연스럽게 처리된다.
즉 이 케이스는 사실상 "로그인이 끊김"만 의미한다.

```
아이콘: Icons.lock_outline
본문: "로그인이 만료됐어요.\n다시 로그인하면 위치를 볼 수 있어요."
버튼: FilledButton("다시 로그인") → 기존 로그인 화면으로 이동
      (이 화면에서 바로 갈 수 있는 로그인 라우트가 없다면 "확인" 라벨로
      대체해 이전 화면으로 pop — 라우팅은 Diana 재량)
```

**③ 그 외 일반 실패 (지도 로딩 실패 등)**
판별: 위 두 가지에 해당하지 않는 모든 에러.

```
아이콘: Icons.error_outline
본문: "위치 정보를 불러오지 못했어요.\n잠시 후 다시 시도해주세요."
버튼: FilledButton("다시 시도") → onPressed: _refresh
```

**정정(2026-08-23)**: 처음 확정 카피에는 "PostgrestException이면 e.message를
보조 텍스트로 표시"가 있었는데, 실제로 이 화면이 호출하는
`get_peer_locations` RPC를 추적해보니 `raise exception`이 전혀 없는 순수
SELECT 함수다(아래 "서버 예외 메시지 전수 조사" 참고). 즉 이 화면에서
`PostgrestException.message`에 담겨 올 수 있는 텍스트는 우리가 정의한
안전한 한글 매핑 대상이 아니라 항상 Postgres/PostgREST 인프라 레벨의 영어
원문(권한 거부, 함수 시그니처 불일치, 타입 캐스팅 오류 등)뿐이다. 화이트리스트로
걸러도 통과할 문구가 없으므로, **e.message는 이 화면에서 아예 노출하지
않는다.** 세 케이스 모두 스택트레이스·영어 예외 메시지·`e.toString()` 원본을
화면에 직접 넣지 않는다.

**검증(Din, 2026-08-24)**: `_classifyError()`/`_ErrorState` 코드를 확인—
아이콘·문구·버튼 라벨·판별 우선순위(네트워크→인증→일반) 모두 확정 카피와
일치. e.message는 어디에도 보간되지 않고 원본 예외는 `developer.log`로만
남김. "다시 로그인" 버튼은 로그인 라우트가 마땅치 않아 로그아웃 후 루트로
pop하는 방식으로 처리했는데(재량 위임한 부분), 로그인 화면이 앱 시작 시
자동으로 뜨는 구조라면 문제없다 — Diana가 이미 확인했다고 가정. 의도대로
구현됨.

### P0-5. 공유 설정 화면이 서버 예외 원문을 스낵바에 그대로 노출한다

**파일**: `share_settings_screen.dart` — `_setMode`, `_pause`, `_resumeNow`

**결정(Plexa, 2026-08-23): 이번 커밋 범위에 포함.** P0-4와 결함 종류가
같은데(서버 원문 예외 노출) 지도 화면만 고치고 정작 위치 공유 설정(프라이버시
조작의 핵심 화면)은 그대로 두면 앞뒤가 안 맞고, 수정 범위도 매핑 4줄로 작다.

세 메서드 모두 `on PostgrestException catch (e)` 블록에서
`_showSnackBar(e.message)`로 서버가 던진 원문 메시지를 그대로 사용자에게
보여준다(이미 배포된 코드). P0-4를 검증하며 위치 기능 마이그레이션 전체의
`raise exception` 메시지를 전수 조사한 결과, 실제로 이 경로로 도달 가능한
메시지는 아래 표의 4개뿐임을 확인했다.

| 함수 | 메시지 | 클라이언트에서 실제 도달 가능? |
|---|---|---|
| `delete_expired_location_history` | `p_retention_days must be a positive integer` | 아니오 — `service_role` 전용 grant, 앱에서 호출 자체가 불가능 |
| `notify_location_ping` | `cannot broadcast a location ping on behalf of another user` | 아니오 — 클라이언트 execute 권한이 없고(HIGH-1 수정), 내부 호출 경로에서는 항상 `auth.uid()`와 일치해 트리거 안 됨 |
| `upsert_location_ping` | `authentication required` / `location must be a Point geography` / `invalid movement_state: %` / `captured_at is required` | 아니오 — `LocationCollectorService`가 `upsertLocationPing()` 호출을 `on Exception`으로 통째로 삼켜서(`location_collector_service.dart:166`) 화면에 절대 나타나지 않음 |
| `upsert_location_ping` | `location sharing is off for all groups; ...` | 아니오 — `LocationRepository._isAllSharesOffError()`가 문자열 매칭으로 걸러 정상 상태(`false` 반환)로 흡수, 에러로 표시 안 됨 |
| `set_location_share_mode` | `authentication required` | 화면에 도달은 가능하나(스낵바) 실제 트리거는 사실상 불가능(이 화면에 오려면 이미 유효 세션 필요) |
| `set_location_share_mode` | `not a member of this group` | **예 — 실제로 도달 가능.** 설정 화면을 띄워둔 채로 그룹에서 제외되는 경쟁 상황이면 스낵바에 영어 원문이 그대로 뜬다 |
| `set_location_share_mode` | `invalid mode: % (expected off|precise|approx)` | 화면에 도달은 가능하나, 모드 값이 항상 고정된 SegmentedButton 값에서만 오므로 버그 없이는 실질적으로 트리거 안 됨 |
| `set_location_share_mode` | `pause_minutes must be a positive integer` | 화면에 도달은 가능하나, 분 값이 항상 고정 프리셋에서만 오므로 버그 없이는 실질적으로 트리거 안 됨 |
| `get_peer_locations` (지도 화면이 호출) | (없음 — `raise exception` 자체가 없는 순수 SELECT) | 해당 없음 → P0-4는 e.message 자체를 아예 노출하지 않는 걸로 정정(위 참고) |

**개선안**: 후보가 4개뿐이라 전부 화이트리스트로 매핑한다(과한 범위가
아님). 매칭 안 되는 나머지는 각 호출부에 이미 있는 기존 폴백 문구를 그대로
쓴다.

```
'authentication required'                     → "로그인이 만료됐어요. 다시 로그인해주세요."
'not a member of this group'                  → "더 이상 이 그룹의 멤버가 아니에요."
'invalid mode: ...' (prefix 'invalid mode:')  → "선택할 수 없는 모드예요. 다시 시도해주세요."
'pause_minutes must be a positive integer'    → "일시중지 시간을 다시 선택해주세요."
그 외 전부                                     → 기존 폴백 문구 유지
                                                 (예: "공유 설정을 변경하지 못했습니다. 다시 시도해주세요.")
```

판별 방식은 `_isAllSharesOffError()`와 동일하게 `e.message`를 소문자로 바꿔
`contains()`로 매칭한다(백엔드가 전용 에러 코드를 아직 정의하지 않았으므로
문자열 매칭이 현재 유일한 수단 — 코드가 붙으면 그걸로 교체 권장).

**검증(Din, 2026-08-24)**: 로직/구조는 문서대로 정확히 구현됐다
(`_mapShareErrorMessage`, 매칭 안 되면 항상 `fallback` 사용). 다만
`'not a member of this group'` 매핑 카피에 내가 처음 넘긴 문구
("이 그룹에서 나가져서 설정을 바꿀 수 없어요")에 문법 오류가 있었다 —
위 표를 "더 이상 이 그룹의 멤버가 아니에요."로 정정했다. Diana에게
`share_settings_screen.dart:33`의 문자열을 이 문구로 바꿔달라고 전달함.

### P0-6. `get_peer_locations`가 off/미설정/일시중지 상대를 제외하게 되면서, 지도·목록에서 그 상대가 설명 없이 사라진다 (Plexa 요청, 2026-08-24 추가)

**파일**: `location_map_screen.dart`

**배경**: 100002 마이그레이션(재리뷰 B/C 수정)부터 `get_peer_locations`는
호출 그룹에서 mode가 off이거나 설정이 없거나 지금 일시중지 중인 상대를
결과에서 완전히 제외한다(수정 전에는 이런 상대의 정밀 좌표가 그대로 새는
버그였다 — 지금 고쳐진 게 맞는 방향). 문제는 클라이언트: `_refresh()`가
`_peers`를 매번 새 결과로 통째로 갈아끼우기 때문에, 지금까지 지도/칩
목록에 보이던 상대가 다음 새로고침에서 결과에 없으면 **아무 설명 없이
조용히 사라진다.** 사용자는 "그룹을 나갔나? 공유를 껐나? 일시중지했나?"를
구분할 방법이 없다.

**정정(Plexa 지적, 2026-08-24): "구분 불가능"이 아니라 "구분 가능하지만
의도적으로 묶는다"가 정확한 근거다.** 처음에는 `location_share_settings`가
"본인 설정만 조회 가능"하게 RLS로 막혀 있으니(다른 사람의 on/off 여부 자체가
최소 노출 대상이라는 것이 100002 마이그레이션 주석에 명시된 설계 의도)
클라이언트가 off와 미설정을 원천적으로 구분할 수 없다고 판단했었다. 하지만
`is_location_paused()`의 SQL을 다시 보면 그렇지 않다:

```sql
select s.paused_until is not null and s.paused_until > now()
from public.location_share_settings s
where s.user_id = p_owner_id
  and s.relationship_group_id = p_relationship_group_id
  and public.is_group_member(p_relationship_group_id, auth.uid())
  and (p_owner_id = auth.uid() or public.can_view_location(p_owner_id, auth.uid()))
```

**함수 계약(일반, 이 화면 맥락과 무관하게 항상 성립)**: 행이 아예 없으면
(=이 그룹에서 한 번도 설정한 적 없음) SQL 스칼라 함수는 `NULL`을 반환하고,
행이 있으면 `paused_until` 조건의 실제 boolean(`false`/`true`)을 반환한다.
**`false`가 뜻하는 건 정확히 "이 그룹에 설정 행이 존재한다"는 사실뿐이다**
— mode가 off인 경우뿐 아니라, precise/approx이면서 지금 일시중지가 아닌
경우(즉 정상적으로 활발히 공유 중인 경우)도 똑같이 `false`를 반환한다.
`false ≠ off`로 함수 자체를 오해하면 안 된다(다른 화면에서 이 함수를 쓸
때 이 계약을 그대로 참고할 것).

**이 화면(P0-6)의 맥락에서의 해석(일반 계약과 구분해서 읽을 것)**: 여기서
`is_location_paused()`를 호출하는 대상은 오직 `get_peer_locations` 결과에
없는(=이미 "숨어 있음"이 확정된) 멤버뿐이다. 숨어 있다는 것 자체가 이미
"off이거나, 미설정이거나, 지금 일시중지 중" 셋 중 하나라는 뜻이므로, 이
좁혀진 후보군 안에서는 `true`=일시중지, 그리고 `false`는 (일시중지가
아니면서 숨어 있으므로) **결과적으로 off로 좁혀진다**, `NULL`=미설정.
즉 "`false`=off"라는 결론은 이 화면의 맥락에서만 성립하는 파생 결론이지,
함수 자체의 계약이 아니다.

호출자가 다른 그룹을 통해 상대를 볼 수 있는 상태(`can_view_location`)이기만
하면 위 조건이 성립해, `false`(이 맥락에서는 사실상 off)와 `NULL`(미설정)이
서로 다른 값으로 갈려서 상대의 off 여부를 그대로 알아낼 수 있다. 이건
`location_share_settings`를 RLS로 가려둔 설계 의도(타인의 on/off 여부를
최소 노출)와 어긋나는 오라클이다.

**오라클 처리 결론 (Rena 검토 완료, 2026-08-24)**: `is_location_paused()`
단독 수정은 불필요하다고 판단됨. `get_share_mode(owner, group)`가 동일한
게이팅(`is_group_member` + `(self or can_view_location)`)으로 이미 `mode`
값 자체를(off를 포함해) 직접 반환하므로, `is_location_paused()`만 막아도
`get_share_mode()`로 그대로 같은 정보를 얻을 수 있어 실효가 없다. 근본
원인은 두 함수가 공유하는 `can_view_location()`의 **크로스-그룹** 판별
("어떤 그룹에서든 활성 공유 중이면 true")이다.

이번 라운드에 잡은 이슈는 총 7건(HIGH-1, HIGH-2, 재리뷰 A/B/C, 입력 검증
누락 E, 그리고 이 오라클)인데, 그중 **크로스-그룹 판별에서 파생된 건 5건
(HIGH-2, A, B, C, 오라클)뿐**이다. HIGH-1(`notify_location_ping`에 execute
권한이 열려 있고 인자로 받은 user_id를 그대로 신뢰한 문제)과 E(accuracy_m/
battery_level 범위 검증 누락)는 각각 권한/신뢰 문제와 입력 검증 문제로,
`can_view_location`과 무관한 별개 원인이다.

이 구분이 다음 라운드 티켓의 근거이므로 명확히 남긴다: **`can_view_location`의
크로스-그룹 판별을 대상 그룹으로 한정하면 5건(HIGH-2/A/B/C/오라클)이 파생된
근본 채널은 막히지만, HIGH-1 같은 권한/신뢰 문제나 E 같은 입력 검증 문제는
그대로 남는다** — 그 두 가지는 각자 이미 별도로 수정됐으므로(100002의
HIGH-1 수정, 100003의 E 수정) 다음 라운드 티켓이 다시 다룰 필요는 없지만,
"`can_view_location`만 고치면 이번 라운드가 다 해결된다"고 오해하지 않도록
범위를 명확히 해둔다. 다음 라운드 티켓 범위는 `is_location_paused` 개별
수정이 아니라 **`can_view_location`의 크로스-그룹 판별을 대상 그룹으로
한정할 수 있는지 검토**하는 것이다.

**그럼에도 이 화면의 결론(중립 문구로 묶기)은 그대로 유지한다 — 오히려
이 사실 때문에 더 중요해졌다.** 구분이 기술적으로 가능하더라도, 화면에서
그 둘을 다른 문구로 보여주면 상대가 원래 감추고 싶어했을 정보(자신이
이 그룹에서 명시적으로 공유를 껐다는 사실)를 노출시키는 셈이다. "구분할 수
없어서 묶는다"가 아니라 **"구분이 가능하더라도, 그 구분 자체가 상대의
프라이버시 정보이므로 의도적으로 묶는다"**가 이 화면 설계의 정확한 근거다.

안전하게(=상대가 감추려 한 정보를 노출하지 않고) 구분해서 보여줘도 되는 것
두 가지:
- **그룹을 나갔는지**: `relationship_members` 로스터(RLS: 같은 그룹 멤버는
  전원 조회 가능, `RelationshipRepository.fetchGroupMembers(groupId)`를
  `group_detail_screen`이 이미 사용 중)로 별도 조회하면 판별된다 — 위치
  공유 설정과 무관한, 이미 공개된 멤버십 정보라 노출 문제가 없다.
- **일시중지 중인지 (`is_location_paused() == true`인 경우만)**: 일시중지는
  "본인이 곧 다시 켤 예정"이라는 적극적 신호이고, 상대도 파악 결과가 이미
  실시간 위치 스냅샷/브로드캐스트로 최근까지 노출되던 상태이므로, `true`만
  콕 집어 알려주는 것은 기존에 없던 정보 노출이 아니다. 반면 `false`/`NULL`을
  구분해서 보여주는 것은 위에서 정리한 새로운 노출이므로 하지 않는다 —
  **`is_location_paused()`의 반환값은 오직 "`true`인가 아닌가"만 사용하고,
  `false`와 `NULL`은 절대 구분하지 않는다.**

**개선안**:

1. 지도 화면 진입/새로고침 시 `get_peer_locations`뿐 아니라
   `RelationshipRepository.fetchGroupMembers(groupId)`도 같이 불러온다.
2. "로스터에는 있고(=아직 그룹 멤버) + `get_peer_locations` 결과엔 없는
   (=지금 위치 안 보임)" 상대를 별도로 계산한다. 로스터에도 없는 상대
   (=그룹을 나감)는 그냥 아무 데도 표시하지 않는다 — 원래 그 그룹에
   없던 사람과 UI상 구분할 필요가 없고, "OO님이 나갔어요" 같은 멤버십
   변경 알림을 새로 만드는 건 이번 범위 밖(별도 기능)이다.
3. "위치 안 보임" 상대 각각에 대해 `is_location_paused(userId, groupId)`를
   호출한다(그룹 규모가 커봐야 커플/가족/친구 단위라 N+1 호출 비용은
   무시할 만하다 — 그룹원이 수십 명 단위로 커지면 그때 배치 RPC로 바꿀 것).
   - `true` → "일시중지" 배지로 표시.
   - `false` 또는 `NULL` → 중립 문구 하나로 통일한다. **이 둘을 구분하는
     분기를 절대 만들지 않는다** — `false`(설정 행 있음=off)와
     `NULL`(설정 행 없음=미설정)을 다르게 보여주면 위에서 정리한 오라클을
     화면이 그대로 사용자에게 노출하는 셈이 된다. "구분이 안 돼서"가 아니라
     "구분해서 보여주면 안 돼서" 묶는다는 점을 코드 리뷰 시에도 놓치지 않을 것.
4. UI: 기존 하단 가로 칩 목록(`_PeerSummaryChip`) 아래에 별도 섹션을
   추가한다(좌표가 없으니 지도 마커로는 표시할 수 없다).

```
섹션 제목: "지금 위치가 보이지 않는 멤버"
(칩 형태는 기존 _PeerSummaryChip과 톤을 맞추되 회색조로 톤다운 —
 좌표 기반 정보가 없으므로 배터리/이동상태 등은 표시하지 않는다)

- 일시중지로 확인된 경우 (is_location_paused == true):
  아이콘: Icons.pause_circle_outline
  문구: "일시중지 중 · 곧 다시 보일 수 있어요"

- 그 외 전부 (off / 미설정 / 판별 불가):
  아이콘: Icons.visibility_off_outlined
  문구: "지금은 위치가 보이지 않아요"
```

두 케이스 모두 "왜"를 추측해서 단정하지 않는다 — 아는 만큼만 말하고, 모르면
중립적으로 말한다. 이게 "최소한 오해는 생기지 않아야 한다"는 요구를 만족하는
유일한 방법이다(백엔드가 온/오프 여부를 타인에게 의도적으로 숨기는 프라이버시
설계이기 때문에, 이 이상 세분화하려는 시도는 추측이 되어버린다).

**Diana 참고**: `LocationRepository`에
`Future<bool?> isLocationPaused(String peerId, String groupId)` 같은 헬퍼
추가 필요(RPC명 `is_location_paused`, 파라미터 `p_owner_id`,
`p_relationship_group_id`). 로스터는 이미 있는
`RelationshipRepository.fetchGroupMembers(groupId)`를 재사용.

### P0-7. 서버/인프라 원문 예외가 화면에 그대로 노출되는 경로 6곳 (Plexa 요청, 2026-08-27 추가 / 2026-08-27 6곳으로 확장)

P0-4(지도 화면)·P0-5(공유 설정 스낵바)와 **정확히 같은 결함 종류** — 서버·
인프라 원문 예외(영어 메시지, PostgREST 코드, 스택트레이스성 텍스트, 내부
함수명)가 화면까지 올라오는 경로다. P0-4/P0-5만 고치고 나머지를 남겨두면
"서버 원문은 화면에 노출되지 않는다"는 방어가 화면마다 들쭉날쭉해진다.

원래 이 중 읽기 경로 3곳은 카피·톤 작업(P2-1) 표에 `${snapshot.error}` 보간
제거를 묻어서 처리하려 했으나, Plexa 판단으로 **별도 P0 항목으로 분리**한다 —
카피 커밋에 섞이면 "이 보안성 수정이 언제·왜 됐는지"가 이력에서 안 보이기
때문이다. **Diana가 커밋B 하나로 6곳을 함께 처리**한다(티켓 granularity =
"한 커밋에서 같이 닫히느냐" 기준이라, 읽기/쓰기를 별도 티켓으로 쪼개지
않는다).

전수 grep 결과 대상은 아래 **6곳**이고, **경로에 따라 처방이 다르다**.

#### 읽기 경로 3곳 — P0-4 방식 (고정 문구, 원본은 로그로만)

`FutureBuilder`의 `snapshot.hasError` 분기에서
`Text('불러오지 못했습니다: ${snapshot.error}')`로 예외 객체를 문자열
보간한다. 세 화면이 호출하는 read 메서드
(`fetchMyGroups`/`fetchGroup`/`fetchGroupMembers`/`fetchMyShareSettings`)는
전부 `.from(...)` 테이블 SELECT라 `raise exception`이 없다 — 즉 여기 담길 수
있는 `PostgrestException.message`는 우리가 정의한 안전한 한글 매핑 대상이
아니라 항상 Postgres/PostgREST 인프라 레벨 영어 원문뿐이다(P0-4의 "서버 예외
메시지 전수 조사" 결론이 그대로 적용). **화이트리스트로 걸러도 통과할 문구가
없으므로 `e.message`를 보조 텍스트로도 노출하지 않는다.**

처방: `${snapshot.error}` 보간을 제거하고 고정 한글 문구만 남긴다. 원본
예외는 `developer.log`(P0-4의 `_refresh` catch 블록과 동일한 방식)로만 남긴다.

| 파일:행 | 현재 | 확정 |
|---|---|---|
| `share_settings_screen.dart:244` | `Center(child: Text('불러오지 못했습니다: ${snapshot.error}'))` | `Center(child: Text('불러오지 못했어요. 잠시 후 다시 시도해주세요.'))` |
| `group_list_screen.dart:81` | `Center(child: Text('불러오지 못했습니다: ${snapshot.error}'))` | `Center(child: Text('불러오지 못했어요. 잠시 후 다시 시도해주세요.'))` |
| `group_detail_screen.dart:201` | `Center(child: Text('불러오지 못했습니다: ${snapshot.error}'))` | `Center(child: Text('불러오지 못했어요. 잠시 후 다시 시도해주세요.'))` |

문구는 P2-1(해요체) 원칙에도 맞으므로 이 커밋으로 톤까지 함께 정리된다 —
**P2-1 표에서는 이 3행을 제외했다(P0-7이 소유)**. 가능하면 P0-4의
`_ErrorState`처럼 아이콘 + "다시 시도" 버튼까지 붙이면 더 좋지만,
`FutureBuilder` 재조회 동선(`setState`로 future 재생성)이 화면마다 필요하므로
1차는 고정 문구 교체 + 로그만으로 충분하다(버튼까지는 Diana 재량).

#### 쓰기 경로 3곳 — P0-5 방식 (화이트리스트 매핑 + 매칭 실패 시 폴백 문구로 덮기)

모두 `group_detail_screen.dart`이며, `on PostgrestException catch (e)`
블록에서 `_showSnackBar(e.message)`로 서버 원문을 스낵바에 직행시킨다.
호출하는 RPC는 `raise exception`이 있는 함수(`090006_relationship_functions.sql`)라
읽기 경로와 달리 **우리가 정의한 도달 가능한 한글 매핑 대상이 존재한다** —
즉 P0-5(`share_settings_screen.dart`의 `_mapShareErrorMessage`)와 같은
"화이트리스트 + 폴백" 처리가 필요하다.

**구조 정정 (Plexa 지적, 2026-08-27)**: `_mapShareErrorMessage`를 본떠
`_mapGroupErrorMessage`를 **새로 만들면 안 된다.** 그러면 "매칭 안 된
메시지는 반드시 폴백으로 덮는다"는 안전장치가 두 벌이 되고, 나중에 한쪽만
고쳐지면 다른 쪽으로 원문이 샌다. 게다가 `_mapShareErrorMessage`는
`share_settings_screen.dart` 파일 private(`_` 접두)이라 재사용도 안 된다.

- **도메인마다 다른 것** = 화이트리스트 *내용*(공유 설정 RPC 메시지 vs 관계
  그룹 RPC 메시지).
- **절대 두 벌이 되면 안 되는 것** = 매칭 방식(소문자 `contains`)과 폴백
  보장 메커니즘.

따라서 **공용 함수 1개 + 도메인 데이터 2개**로 간다.

**① 공용 모듈** — 신규 파일 `app/lib/core/errors/server_error_message.dart`

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST가 전달한 서버 예외 메시지를, 미리 정의한 화이트리스트에 있으면
/// 사용자용 한글 문구로 바꾸고, **없으면 무조건 `fallback`으로 덮는다.**
/// 서버가 던진 원문이 화면에 그대로 노출되는 경로를 한 군데에서 차단하기
/// 위한 유일한 진입점이다(Din UX 리뷰 P0-4/P0-5/P0-7). 도메인별로 다른 것은
/// `whitelist`의 내용뿐이고, "매칭 방식(소문자 contains) + 매칭 실패 시 폴백
/// 보장"은 이 함수 하나로만 존재한다 — 도메인마다 비슷한 함수를 복제하지 말 것.
///
/// 판별이 문자열 `contains`인 이유: 백엔드가 아직 전용 에러 코드(errcode/detail)를
/// 정의하지 않아, plain `raise exception` 메시지 매칭이 현재로선 유일한 수단이다.
/// 백엔드가 에러 코드를 붙이면 이 함수의 매칭을 코드 기반으로 바꾸면 되고,
/// 호출부와 도메인 데이터는 그대로 둘 수 있다.
///
/// `whitelist`는 삽입 순서대로 검사된다(첫 매칭 채택). 한 키가 다른 키의
/// 부분문자열이면 더 구체적인 것을 앞에 둘 것.
///
/// 참고: `LocationRepository._isAllSharesOffError()`도 같은 "소문자 contains"
/// 관행을 쓰지만 그건 메시지 *매핑*이 아니라 정상 상태 여부의 *불리언 판별*이라
/// 목적이 달라 이 함수로 합치지 않는다 — 관행만 같다.
String mapServerErrorMessage(
  PostgrestException e, {
  required Map<String, String> whitelist,
  required String fallback,
}) {
  final message = e.message.toLowerCase();
  for (final entry in whitelist.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return fallback;
}
```

**② 도메인 데이터 2개** — 각 feature 안에 상수로 둔다(공용 모듈은 데이터를
모른다).

```dart
// app/lib/features/location/data/server_error_messages.dart (또는
// share_settings_screen.dart 파일 상단 — 위치는 Diana 재량, 단 재사용 가능하게
// public 또는 최소 라이브러리 스코프로)
const shareSettingsServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
  'not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
  'invalid mode:': '선택할 수 없는 모드예요. 다시 시도해주세요.',
  'pause_minutes must be a positive integer': '일시중지 시간을 다시 선택해주세요.',
};

// app/lib/features/relationships/... 안에
const relationshipGroupServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
  'only members of the group can create invitations':
      '이 그룹의 멤버만 초대 코드를 만들 수 있어요.',
  'not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
  'only the group owner can remove members':
      '그룹을 만든 사람만 멤버를 내보낼 수 있어요.',
  'use leave_relationship_group': '자기 자신은 "그룹 탈퇴"로 나가야 해요.',
};
```

**③ 기존 P0-5 코드도 이 공용 함수로 옮긴다(같은 커밋B).** 현재
`share_settings_screen.dart`의 `_mapShareErrorMessage`(if/else 4단)는
`mapServerErrorMessage(e, whitelist: shareSettingsServerErrors, fallback: …)`
호출로 대체한다. `_mapShareErrorMessage`라는 파일 private 래퍼를 남겨도 되고
(본문만 공용 함수 위임), 3개 호출부에서 직접 공용 함수를 불러도 된다 — 어느
쪽이든 **매칭+폴백 로직의 사본이 코드에 하나만 있으면 된다.** 이 이관은
P0-7의 목적(원문 노출 경로를 한 군데로 모으기)과 같은 커밋에 들어가는 게 맞다.

전수 조사 결과 관계 그룹 3개 RPC가 `raise exception`으로 던지는 메시지 전부
(위 `relationshipGroupServerErrors`가 이 표를 그대로 반영한다):

| RPC | 원문 메시지 | 실사용 도달 가능? | 확정 카피 |
|---|---|---|---|
| `create_relationship_invitation` | `authentication required` | 사실상 불가(이 화면 = 유효 세션) | `'로그인이 만료됐어요. 다시 로그인해주세요.'` |
| `create_relationship_invitation` | `only members of the group can create invitations` | 드묾(초대 버튼은 owner에게만 노출 → owner는 항상 멤버, 화면 열어둔 채 제외되는 경쟁 상황만) | `'이 그룹의 멤버만 초대 코드를 만들 수 있어요.'` |
| `leave_relationship_group` | `authentication required` | 사실상 불가 | `'로그인이 만료됐어요. 다시 로그인해주세요.'` |
| `leave_relationship_group` | `not a member of this group` | **예 — 화면 열어둔 채 다른 기기/멤버가 나를 내보내면 도달** | `'더 이상 이 그룹의 멤버가 아니에요.'` |
| `remove_relationship_member` | `authentication required` | 사실상 불가 | `'로그인이 만료됐어요. 다시 로그인해주세요.'` |
| `remove_relationship_member` | `use leave_relationship_group() to remove yourself` | 사실상 불가(내보내기 버튼은 `member.userId != currentUserId`일 때만 노출) — 도달해도 내부 함수명이 그대로 새므로 매핑 필수 | `'자기 자신은 "그룹 탈퇴"로 나가야 해요.'` |
| `remove_relationship_member` | `only the group owner can remove members` | 드묾(내보내기 버튼은 owner에게만 노출 → 소유권 이전 기능이 아직 없어 경쟁 상황도 거의 없음) | `'그룹을 만든 사람만 멤버를 내보낼 수 있어요.'` |

처방: 세 호출부의 `on PostgrestException catch (e)` 블록을 아래로 바꾼다.
공용 함수 `mapServerErrorMessage`에 관계 그룹 도메인 데이터
(`relationshipGroupServerErrors`)와 각 호출부의 `fallback`(= P2-1에서 해요체로
정리된 기존 폴백 문구)을 넘긴다. 매칭 안 되는 나머지는 `fallback`으로 덮인다.

| 파일:행 | 현재 | 확정 |
|---|---|---|
| `group_detail_screen.dart:65` (`_createInvitation`) | `_showSnackBar(e.message);` | `_showSnackBar(mapServerErrorMessage(e, whitelist: relationshipGroupServerErrors, fallback: '초대 코드를 만들지 못했어요. 다시 시도해주세요.'));` |
| `group_detail_screen.dart:128` (`_removeMember`) | `_showSnackBar(e.message);` | `_showSnackBar(mapServerErrorMessage(e, whitelist: relationshipGroupServerErrors, fallback: '멤버를 내보내지 못했어요. 다시 시도해주세요.'));` |
| `group_detail_screen.dart:149` (`_leaveGroup`) | `_showSnackBar(e.message);` | `_showSnackBar(mapServerErrorMessage(e, whitelist: relationshipGroupServerErrors, fallback: '그룹에서 나가지 못했어요. 다시 시도해주세요.'));` |

> 각 호출부의 `} catch (e) {` (비-Postgrest) 폴백 문구(`:67`, `:130`, `:152`)는
> P2-1 표에서 이미 해요체로 정리 대상이다 — 위 `fallback:` 인자 문구와
> **글자까지 동일하게** 맞춰서, Postgrest든 아니든 사용자가 보는 문구가
> 같도록 한다.

#### `revokeInvitation`는 이번 범위 아님

`RelationshipRepository.revokeInvitation`(`:123`)도 쓰기 RPC지만
`group_detail_screen`에서 `_showSnackBar(e.message)` 경로로 노출되지 않는다
(현재 이 화면에 초대 취소 UI 없음). 초대 취소 UI가 생기면 그때 같은 헬퍼로
감싼다.

---

## P1 — 이해도·진입 흐름 개선

### P1-1. "정밀"/"대략" 모드 차이에 대한 설명이 화면 어디에도 없다

**파일**: `share_settings_screen.dart` — `_GroupShareCard`

SegmentedButton에 "정밀"/"대략" 레이블만 있고 차이(정확한 좌표 vs ~100m 격자
반올림)를 설명하는 텍스트가 없다. 지도 화면(`_buildApproxCircles`의 주석)에는
그 의미가 코드 주석으로만 존재한다. 사용자는 두 옵션의 실질적 차이를 추측해야
한다.

**개선안**: SegmentedButton 아래에 선택된 모드에 따라 바뀌는 보조 설명 1줄
추가.

- 정밀 선택 시: `"정확한 위치가 실시간으로 보여요."`
- 대략 선택 시: `"실제 위치에서 반경 약 100m 이내로 뭉뚱그려 보여요."`
- 끄기 선택 시: `"이 그룹에는 내 위치가 전혀 보이지 않아요."`

### P1-2. 일시중지 종료 시각이 `DateTime.toLocal()` 원본 그대로 노출된다

**파일**: `share_settings_screen.dart:314`

```dart
Text('${setting.pausedUntil!.toLocal()} 까지 일시중지됨')
```

`2026-08-23 15:32:00.123456` 형태의 비정제 문자열이 그대로 찍힌다.

**개선안**: 오늘 안이면 `"오후 3:32까지 일시중지됨"`, 다음날 이후로 넘어가면
`"8/24 오후 3:32까지 일시중지됨"` 형태로 포맷. (예: `intl` 패키지 `DateFormat`
사용 — 프로젝트에 이미 의존성이 있는지 Diana 확인 필요.)

### P1-3. 오래된(stale) 위치에 대한 시각적 구분이 없다

**파일**: `location_map_screen.dart` — `_buildMarkers`, `_PeerSummaryChip`

마커 색은 정밀(파랑)/대략(주황)만 구분하고, 신선도는 `freshnessLabel()`
텍스트로만("3시간 전", "1일 전") 표현된다. 지도를 훑어볼 때 텍스트를 일일이
읽지 않으면 오래된 위치도 방금 위치와 똑같이 보여, "지금 여기 있다"고 오해하기
쉽다.

**개선안**: `receivedAt` 기준 30분 이상 지난 피어는 시각적으로 톤다운한다.

- 마커: opacity를 낮추거나(`Marker.alpha`, google_maps_flutter 지원) 별도
  회색조 아이콘 사용
- `_PeerSummaryChip`: 배경색을 중립 회색으로, freshness 텍스트 앞에
  `Icons.history` 아이콘 추가, 텍스트 스타일에 강조색 대신 `bodySmall` +
  `onSurfaceVariant` 사용
- 기준값(30분)은 하드코딩 상수로 두고 이름 붙여 관리 (`_staleThreshold`)

### P1-4. 권한 거부 상태의 재시도 안내가 약하다

**파일**: `location_permission_screen.dart:98-104`

`denied` 상태 배너 문구가 `"위치 권한이 거부되었어요. 다시 시도해주세요."` 인데,
바로 아래 버튼 라벨은 여전히 `"위치 권한 허용"`이라 "다시 시도"가 정확히 뭘
누르라는 건지 시각적으로 연결되지 않는다. 또한 `"나중에 하기"`를 누르면
어떤 결과가 되는지(위치 공유 기능을 쓸 수 없다는 것) 안내가 없다.

**개선안**:
- denied 배너 문구를 `"위치 권한이 거부되었어요. 아래 버튼으로 다시 요청할 수 있어요."` 로 바꿔 버튼과 연결
- "나중에 하기" 버튼 근처에 보조 캡션 추가: `"나중에 '위치 공유 설정'에서 언제든 다시 켤 수 있어요."`

### P1-5. 그룹 상세 화면에서 해당 그룹의 공유 설정으로 바로 가는 진입점이 없다

**파일**: `group_detail_screen.dart`

`"위치 지도 보기"` 버튼은 있지만(상대 위치를 보는 동선), 정작 "나는 이 그룹에
내 위치를 얼마나 공유할지" 설정하려면 뒤로 나가서 홈 → "위치 공유 설정" →
그룹 목록에서 해당 카드를 다시 찾아야 한다. 그룹 컨텍스트가 이미 있는 화면에서
가장 관련 있는 설정으로 못 가는 것은 불필요한 이동이다.

**개선안**: `"위치 지도 보기"` 버튼 옆(또는 지도 화면 AppBar actions)에
아이콘 버튼 추가: `Icons.tune` + tooltip `"내 공유 설정"` → `ShareSettingsScreen`으로
이동하되, 가능하면 해당 그룹 카드로 스크롤/포커스(1차로는 화면 진입만으로도
충분, 스크롤 포커스는 P2로 미뤄도 됨).

### P1-6. 홈 화면에 전체 공유 상태 요약이 없다

**파일**: `home_screen.dart`

홈 화면의 "위치 공유 설정" 버튼은 다른 버튼들과 동일한 톤(`OutlinedButton`)이라
지금 공유 중인지 아닌지 홈 화면만 봐서는 전혀 알 수 없다. 프라이버시 기능
특성상 앱을 열 때마다(특히 아무 것도 안 눌러도) 현재 공유 여부를 인지할 수
있으면 신뢰도가 높아진다.

**개선안**: `"위치 공유 설정"` 버튼의 subtitle 또는 버튼 하단에 상태 캡션 1줄
추가. P0-1에서 정의한 요약 로직을 재사용:

```
"위치 공유 설정"
    ↳ "OO, OO에게 공유 중" 또는 "공유 꺼짐" (캡션, bodySmall, secondary 색)
```

구현 우선순위상 P0-1(공유 설정 화면 배너)이 선행되어야 하므로 P1로 분류했지만,
같은 로직/문구를 재사용하면 되므로 추가 설계 비용은 작다.

### P1-7. "위치 수집"이라는 내부 용어가 사용자 문구에 그대로 노출된다

**파일**: `share_settings_screen.dart:211` (`SwitchListTile` title)

`"내 위치 수집"`은 개발자 관점 용어(수집기/collector)이고, 사용자에게 중요한
개념은 "공유"다. 같은 화면 안에서도 subtitle은 "전송"이라는 표현을 쓰고,
그룹 카드는 "공유"라는 표현을 쓴다 — 세 단어(수집/전송/공유)가 한 화면에서
같은 대상을 가리키며 혼재한다.

**개선안**: 사용자 대상 문구는 전부 "공유"로 통일.

```
title: "내 위치 공유"
subtitle: "이 스위치를 켜야 아래에서 선택한 그룹에 위치가 전달돼요. "
          "그룹별로 켜고 끄려면 아래에서 설정하세요."
```

(내부 클래스/메서드명 `LocationCollectorService`, `_toggleCollector` 등 코드
식별자는 그대로 두어도 무방 — 사용자 노출 문자열만 통일 대상.)

---

## P2 — 톤·디테일

### P2-1. 해요체/합쇼체가 화면마다 혼용된다

예: `"위치 권한이 필요해요"`(해요체) vs `"불러오지 못했습니다"`,
`"속한 관계 그룹이 없습니다"`, `"...전송합니다"`(합쇼체)가 같은 앱, 심지어
같은 화면(`share_settings_screen.dart`) 안에 공존한다.

**개선안**: 프라이밍 화면의 톤(해요체 — "~해요", "~돼요", "~있어요")으로
전체 통일 권장. 커플/가족 대상 앱이라 합쇼체보다 해요체가 제품 톤에 맞는다.
일괄 치환 대상 예시:

- "불러오지 못했습니다" → "불러오지 못했어요"
- "속한 관계 그룹이 없습니다" → "속한 관계 그룹이 없어요"
- "...서버에 전송합니다" → "...서버로 전달해요"
- "그룹 상세" (AppBar 타이틀류는 명사형이라 예외, 톤 통일 대상 아님)

### P2-2. 지도 로딩 스피너가 매 refresh마다 지도 위 상단에 겹쳐 뜬다

**파일**: `location_map_screen.dart:255-261`

앱이 foreground로 복귀할 때마다(`didChangeAppLifecycleState`) `_refresh()`가
불려 매번 스피너가 지도 위에 잠깐 나타난다. 이미 마커가 표시된 상태에서
매번 화면 중앙 상단에 로딩 인디케이터가 깜빡이면 산만하다.

**개선안**: 최초 로드(`_peers`가 비어있고 아직 한 번도 안 불러온 경우)에만
전체 화면형 로딩을 쓰고, 이미 데이터가 있는 상태의 백그라운드 refresh는
AppBar의 새로고침 아이콘을 잠깐 스피너로 바꾸는 정도의 미세한 표시로 낮춘다.

### P2-3. 지도에서 "내 위치로 이동" 동선이 없다

**파일**: `location_map_screen.dart`

`myLocationButtonEnabled: false`로 꺼져 있고 대체 버튼도 없다. 상대 위치만
보고 내 위치 기준을 잡을 수 없어 지도 탐색이 불편할 수 있다. (이번 라운드
범위 밖일 수 있어 P2로 분류 — 필요시 Phase 2로 이연 가능.)

### P2-4. 지도 화면에 pull-to-refresh가 없다

설정 화면(`share_settings_screen.dart`)은 `RefreshIndicator`를 쓰는데 지도
화면은 AppBar 아이콘으로만 새로고침한다. 두 화면의 새로고침 상호작용 방식을
맞추면 학습 비용이 줄어든다. (지도 위에서 pull-to-refresh 제스처가
GoogleMap의 팬 제스처와 충돌할 수 있어 AppBar 아이콘 유지 + 존재를 더 눈에
띄게 하는 정도로 절충 가능 — Diana 재량.)

### P2-5. "정밀" 표기 통일

지시문/기획 문서에서는 "정확"이라는 단어도 쓰이는데 실제 구현은 "정밀"로
되어 있다. 기능적으로 문제는 없으나, 앞으로 기획 문서·QA 테스트 케이스·화면
문구에서 전부 "정밀"로 통일해서 부르기를 제안한다(현재 구현 기준을
표준으로 채택).

---

## Diana 구현 시 참고

- P0-1, P0-2, P1-6은 모두 "실제 공유 상태 요약" 로직을 공유하므로, 별도
  헬퍼(예: `ShareStatusSummary.compute(groups, settings, collectorRunning)`)로
  뽑아 `share_settings_screen.dart`와 `home_screen.dart`에서 재사용하는 것을
  권장한다.
- 카피는 위에 적힌 문안을 그대로 써도 되고, 톤(P2-1) 통일 원칙만 지키면 문구
  자체는 자유롭게 다듬어도 된다.
- 순서 제안: P0 전체 → P1-1/P1-2(그룹 카드 관련, P0-2와 같은 위젯) → 나머지
  P1 → P2.

---

## 카피·톤 확정 (Din, 2026-08-27)

Plexa 배분으로 아래 문구를 **확정**한다: P1-7(내부 용어 "위치 수집" 대체),
P2-1(해요체/합쇼체 통일), P2-5("정밀" 표기 통일), P1-4(권한 거부 재시도 안내
강화), P2-6("추방" → "내보내기" 어휘 순화, Plexa 승인 2026-08-27). 아래 문구는
Diana가 **그대로 붙여넣을 수 있는 최종안**이다. 톤만 지키면 자유롭게 다듬어도
된다는 기존 단서(위 "Diana 구현 시 참고")보다 이 섹션이 우선한다 — 이 항목들의
문구는 이대로 확정한다.

**P0-7 관계**: 서버·인프라 원문 예외가 화면까지 노출되는 6곳(읽기 경로 3 +
쓰기 경로 3)은 Plexa 판단으로 **P0-7로 분리**됐다(위 P0 섹션 참고). 이 중
읽기 경로 3곳(`'불러오지 못했습니다: ${snapshot.error}'`)은 원래 아래 P2-1
표에 있었으나 제외했고, 쓰기 경로 3곳(`group_detail_screen.dart`의
`_showSnackBar(e.message)`)은 이번에 새로 합류했다. Diana가 커밋B 하나로 6곳을
함께 처리한다.

### 용어 원칙 (P1-7 + P2-5 공통)

곁에의 위치 기능 사용자 문구에서 쓰는 단어를 아래로 고정한다.

| 개념 | 쓸 단어 | 쓰지 않을 단어 |
|---|---|---|
| 기능·상태를 가리키는 명사 | **공유** ("위치 공유", "공유 중", "공유 꺼짐", "내 위치 공유") | "수집", "전송" |
| 내 위치 데이터가 상대에게 가는 동작 | **보여요 / 전달돼요** | "전송돼요", "송신" |
| 그룹별 공개 정확도 모드 | **정밀 / 대략 / 끄기** (고정) | "정확", "상세", "러프" |

- "수집"·"전송"은 개발자 관점 용어(collector)다. 코드 식별자
  (`LocationCollectorService`, `_toggleCollector`, `location_collector_service.dart`
  등)와 `developer.log` name 문자열은 **그대로 둔다** — 사용자에게 보이는
  문자열만 통일 대상이다.
- "정밀"은 **모드의 이름**이다. 설명 문장 안에서 "정확한 위치"처럼 결과를
  풀어 설명하는 표현은 허용하지만(예: `shareModeDescription('precise')`의
  "정확한 위치가 실시간으로 보여요."는 유지), 모드를 **지칭**할 때는 항상
  "정밀"이라고 쓴다. 기획 문서·QA 테스트 케이스명·디자인 문서도 전부
  "정밀"로 통일한다(현재 구현 표기를 표준으로 채택). "정확 모드",
  "정확도 높음" 같은 표현은 쓰지 않는다.

### P1-7. "위치 수집" → "내 위치 공유"

**파일**: `app/lib/features/location/settings/share_settings_screen.dart`,
`app/lib/features/location/share_status_summary.dart`

`share_settings_screen.dart:256` — 상단 스위치 title

```
현재: title: const Text('내 위치 수집'),
확정: title: const Text('내 위치 공유'),
```

`share_settings_screen.dart:257-261` — 같은 스위치 subtitle (합쇼체 "전송합니다"도 함께 정리)

```
현재:
  subtitle: const Text(
    '이 기기의 위치를 주기적으로 서버에 전송합니다. '
    '실제로 상대에게 보이려면 아래에서 최소 한 그룹을 '
    '"정밀" 또는 "대략"으로 켜야 해요.',
  ),

확정:
  subtitle: const Text(
    '이 스위치를 켜야 아래에서 켠 그룹에 내 위치가 전달돼요. '
    '그룹별 공개 범위(정밀·대략·끄기)는 아래에서 따로 설정해요.',
  ),
```

`share_settings_screen.dart:352` — P0-2 경고 문구(수집 → 공유)

```
현재: '⚠ 위치 수집이 꺼져 있어 이 설정은 적용되지 않아요.',
확정: '⚠ 내 위치 공유가 꺼져 있어 이 설정은 아직 적용되지 않아요.',
```

`share_status_summary.dart:39` — collectingOnly 케이스 메시지(수집 → 공유)

```
현재:
  message: '위치 수집은 켜져 있지만, 아직 공유 중인 그룹이 없어요. 아래에서 그룹을 선택해주세요.',
확정:
  message: '내 위치 공유는 켜져 있지만, 공유할 그룹을 아직 안 골랐어요. 아래에서 그룹을 켜주세요.',
```

이 4곳을 바꾸면 위치 기능에서 사용자에게 보이는 "수집"·"전송"이 모두 없어진다
(2026-08-27 기준 전수 확인: 위 4곳 + subtitle 1곳이 전부).

### P2-1. 해요체로 통일

**톤 원칙**

- 앱 전체 사용자 문구는 **해요체**로 통일한다 — "~해요", "~돼요", "~있어요",
  "~예요/이에요", "~까요?". 커플·가족·친구 대상 앱이라 합쇼체("~습니다",
  "~합니다")보다 해요체가 제품 톤에 맞는다.
- **예외 1 (명사구 제목)**: AppBar 타이틀·다이얼로그 제목 등 명사로 끝나는
  라벨은 그대로 둔다 — "위치 권한", "위치 공유 설정", "그룹 상세",
  "멤버 내보내기"(P2-6로 "추방"에서 변경), "그룹 탈퇴".
- **예외 2 (버튼·세그먼트 라벨)**: 명사 또는 동사원형으로 끝나는 짧은 액션
  라벨은 그대로 둔다 — "다시 시도", "다시 로그인", "닫기", "복사하고 닫기",
  "끄기", "정밀", "대략", "즉시 재개", "N분만 일시중지".
- **예외 3 (개발자 전용 문자열)**: 사용자에게 렌더되지 않는 문자열은 대상이
  아니다 — `developer.log`의 `name`/메시지, `FormatException`·`Exception`
  생성자 메시지(예: `geo_point.dart:57` "알 수 없는 geography 형식입니다: …").
- **마침표**: 스낵바·배너처럼 완결된 안내 문장은 마침표를 유지하고, 한 줄
  캡션·버튼 라벨은 마침표를 생략한다.

**화면별 수정 카피 표** — `현재` 문자열을 `확정` 문자열로 그대로 교체.
행 경로는 `app/lib/` 기준. 줄 번호는 2026-08-27 기준이며, 편집 중 밀리면
문자열로 찾는다.

파일:행 오름차순(경로 알파벳 → 줄 번호)으로 정렬했다 — Diana가 한 파일씩
훑으며 위→아래로 치환하면 된다.

| 파일:행 | 현재 | 확정 |
|---|---|---|
| `features/auth/presentation/screens/login_screen.dart:52` | `'로그인 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'로그인 중 문제가 생겼어요. 다시 시도해주세요.'` |
| `features/auth/presentation/screens/login_screen.dart:109` | `'비밀번호는 6자 이상이어야 합니다.'` | `'비밀번호는 6자 이상이어야 해요.'` |
| `features/auth/presentation/screens/signup_screen.dart:60` | `'가입 확인 이메일을 보냈습니다. 이메일 확인 후 로그인해주세요.'` | `'가입 확인 이메일을 보냈어요. 메일을 확인한 뒤 로그인해주세요.'` |
| `features/auth/presentation/screens/signup_screen.dart:69` | `'회원가입 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'회원가입 중 문제가 생겼어요. 다시 시도해주세요.'` |
| `features/auth/presentation/screens/signup_screen.dart:115` | `'비밀번호는 6자 이상이어야 합니다.'` | `'비밀번호는 6자 이상이어야 해요.'` |
| `features/auth/presentation/screens/signup_screen.dart:127` | `'비밀번호가 일치하지 않습니다.'` | `'비밀번호가 일치하지 않아요.'` |
| `features/home/presentation/screens/home_screen.dart:89` | `'$email 님, 환영합니다.'` | `'$email 님, 환영해요.'` |
| `features/home/presentation/screens/home_screen.dart:134` | `'버킷리스트, 스토리 업로드 기능은 다음 라운드에서 추가됩니다.'` | `'버킷리스트, 스토리 업로드는 다음 업데이트에서 추가될 예정이에요.'` |
| `features/location/map/location_map_screen.dart:371` | `'아직 공유된 위치가 없습니다. 상대가 위치 공유를 켜면 여기에 표시돼요.'` | `'아직 공유된 위치가 없어요. 상대가 위치 공유를 켜면 여기에 표시돼요.'` |
| `features/location/settings/share_settings_screen.dart:142` | `fallback: '공유 설정을 변경하지 못했습니다. 다시 시도해주세요.',` | `fallback: '공유 설정을 바꾸지 못했어요. 다시 시도해주세요.',` |
| `features/location/settings/share_settings_screen.dart:145` | `'공유 설정을 변경하지 못했습니다. 다시 시도해주세요.'` | `'공유 설정을 바꾸지 못했어요. 다시 시도해주세요.'` |
| `features/location/settings/share_settings_screen.dart:163` | `'$minutes분 동안 위치 공유를 일시중지합니다.'` | `'$minutes분 동안 위치 공유를 일시중지해요.'` |
| `features/location/settings/share_settings_screen.dart:168` | `fallback: '일시중지 설정에 실패했습니다. 다시 시도해주세요.',` | `fallback: '일시중지하지 못했어요. 다시 시도해주세요.',` |
| `features/location/settings/share_settings_screen.dart:171` | `'일시중지 설정에 실패했습니다. 다시 시도해주세요.'` | `'일시중지하지 못했어요. 다시 시도해주세요.'` |
| `features/location/settings/share_settings_screen.dart:187` | `'공유를 다시 시작합니다.'` | `'공유를 다시 시작했어요.'` |
| `features/location/settings/share_settings_screen.dart:192` | `fallback: '공유를 다시 시작하지 못했습니다. 다시 시도해주세요.',` | `fallback: '공유를 다시 시작하지 못했어요. 다시 시도해주세요.',` |
| `features/location/settings/share_settings_screen.dart:195` | `'공유를 다시 시작하지 못했습니다. 다시 시도해주세요.'` | `'공유를 다시 시작하지 못했어요. 다시 시도해주세요.'` |
| `features/location/settings/share_settings_screen.dart:278` | `'속한 관계 그룹이 없습니다.'` | `'아직 속한 관계 그룹이 없어요.'` |
| `features/location/share_status_summary.dart:27` | `'현재 위치 공유가 꺼져 있어요. 아무에게도 보이지 않습니다.'` | `'현재 위치 공유가 꺼져 있어요. 아무에게도 보이지 않아요.'` |
| `features/relationships/data/relationship_repository.dart:106` | `'존재하지 않는 초대 코드입니다.'` | `'존재하지 않는 초대 코드예요.'` |
| `features/relationships/presentation/screens/group_create_screen.dart:54` | `'그룹 생성 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'그룹을 만들지 못했어요. 다시 시도해주세요.'` |
| `features/relationships/presentation/screens/group_detail_screen.dart:67` | `'초대 생성 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'초대 코드를 만들지 못했어요. 다시 시도해주세요.'` |
| `features/relationships/presentation/screens/group_detail_screen.dart:77` | `const Text('초대 코드가 생성되었습니다')` | `const Text('초대 코드를 만들었어요')` |
| `features/relationships/presentation/screens/group_detail_screen.dart:98` | `'초대 코드를 복사했습니다.'` | `'초대 코드를 복사했어요.'` |
| `features/relationships/presentation/screens/group_detail_screen.dart:130` | `'멤버 추방 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'멤버를 내보내지 못했어요. 다시 시도해주세요.'` (P2-6와 함께) |
| `features/relationships/presentation/screens/group_detail_screen.dart:139` | `'정말 이 그룹에서 나가시겠어요? 마지막 멤버라면 그룹이 삭제됩니다.'` | `'정말 이 그룹에서 나갈까요? 마지막 멤버가 나가면 그룹도 사라져요.'` |
| `features/relationships/presentation/screens/group_detail_screen.dart:152` | `'탈퇴 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'그룹에서 나가지 못했어요. 다시 시도해주세요.'` |
| `features/relationships/presentation/screens/group_list_screen.dart:94` | `'아직 속한 관계 그룹이 없습니다.\n오른쪽 아래 + 버튼으로 그룹을 만들거나,\n메일 아이콘으로 초대 코드를 입력해보세요.'` | `'아직 속한 관계 그룹이 없어요.\n오른쪽 아래 + 버튼으로 그룹을 만들거나,\n메일 아이콘으로 초대 코드를 입력해보세요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:55` | `'초대 정보를 불러오지 못했습니다. 다시 시도해주세요.'` | `'초대 정보를 불러오지 못했어요. 다시 시도해주세요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:79` | `'초대 수락 중 문제가 발생했습니다. 다시 시도해주세요.'` | `'초대를 수락하지 못했어요. 다시 시도해주세요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:87` | `'이미 이 그룹의 멤버입니다.'` | `'이미 이 그룹의 멤버예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:90` | `'만료된 초대입니다.'` | `'만료된 초대예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:93` | `'이미 처리되었거나 취소된 초대입니다.'` | `'이미 처리됐거나 취소된 초대예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:96` | `'존재하지 않는 초대 코드입니다.'` | `'존재하지 않는 초대 코드예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:104` | `'이미 수락된 초대입니다.'` | `'이미 수락된 초대예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:106` | `'취소된 초대입니다.'` | `'취소된 초대예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:108` | `'만료된 초대입니다.'` | `'만료된 초대예요.'` |
| `features/relationships/presentation/screens/invitation_accept_screen.dart:111` | `'만료된 초대입니다.'` | `'만료된 초대예요.'` |

> **P0-7로 이관**: `'불러오지 못했습니다: ${snapshot.error}'` 3곳
> (`share_settings_screen.dart:244`, `group_list_screen.dart:81`,
> `group_detail_screen.dart:201`)과 `group_detail_screen.dart`의
> `_showSnackBar(e.message)` 3곳(`:65`, `:128`, `:149`)은 서버·인프라 원문
> 예외 노출 문제라 위 P0 섹션의 **P0-7**(총 6곳)로 분리됐다. Diana가 커밋B
> 하나로 처리하며, 읽기 경로 확정 문구
> (`'불러오지 못했어요. 잠시 후 다시 시도해주세요.'`)로 톤까지 함께
> 정리되므로 이 표에는 넣지 않는다.
>
> 단, 위 P2-1 표의 `group_detail_screen.dart:130`(`'멤버를 내보내지 못했어요…'`),
> `:152`(`'그룹에서 나가지 못했어요…'`), `:67`(`'초대 코드를 만들지 못했어요…'`)
> 는 P0-7 쓰기 경로 헬퍼의 `fallback:` 인자 문구와 **글자까지 같아야** 하므로,
> Diana는 두 곳을 같은 값으로 맞춘다(어느 커밋에서 손대든 최종 문자열 동일).

> **`relationship_repository.dart:106`**: `RelationshipException` 메시지가
> 화면까지 그대로 노출되는 경로인지 Diana가 확인하고, 화면 쪽
> (`invitation_accept_screen.dart`)에서 이미 코드 매핑으로 덮인다면 repo
> 문자열은 손대지 않아도 된다. 노출 경로가 있으면 위 표대로 교체.

### P2-5. "정밀" 표기 통일 — 확정

- 2026-08-27 기준 전수 확인 결과, **현재 사용자 문구는 이미 전부 "정밀"로
  통일되어 있다** (SegmentedButton 라벨 `'정밀'`, 권한 프라이밍 화면
  "정밀도(정밀/대략)", 수집 스위치 subtitle의 `"정밀" 또는 "대략"`).
  따라서 **코드 변경은 없다.**
- `shareModeDescription('precise')`의 `'정확한 위치가 실시간으로 보여요.'`는
  모드를 지칭하는 게 아니라 결과를 설명하는 문장이므로 **그대로 유지**한다
  (위 "용어 원칙" 참고).
- 확정 사항: 앞으로 **기획 문서·QA 테스트 케이스명·디자인 문서·PR 설명**에서
  이 모드를 부를 때는 예외 없이 **"정밀"**로 쓴다. "정확 모드", "정확도
  모드" 같은 표기를 새로 만들지 않는다. Tom은 위치 관련 테스트 케이스명에
  "정확" 대신 "정밀"을 쓴다(현재 `peer_location_test.dart`의 "정확히
  임계값…"은 부사라 대상 아님).

### P1-4. 권한 거부 상태 재시도 안내 강화 — 확정

**파일**: `app/lib/features/location/permission/location_permission_screen.dart`

목표: (a) denied 배너 문구와 바로 아래 버튼을 **말로 연결**하고, (b) "나중에
하기"를 눌렀을 때의 결과와 되돌리는 법을 알려준다. 권한 요청 범위
(`requestWhileInUse()`)는 그대로 — 카피만 강화한다.

**① denied 배너 (`:100-104` 블록의 message)**

```
현재: message: '위치 권한이 거부되었어요. 다시 시도해주세요.',
확정: message: '위치 권한이 거부됐어요. 아래 "위치 권한 다시 요청" 버튼으로 한 번 더 요청할 수 있어요.',
```

**② 권한 요청 버튼 라벨 (`:107-111`)** — denied 상태에서는 "다시 요청"으로 바뀌어 배너와 연결된다

```
현재:
  label: Text(_isRequesting ? '요청 중...' : '위치 권한 허용'),

확정:
  label: Text(
    _isRequesting
        ? '요청 중…'
        : (_lastResult == LocationPermissionResult.denied
            ? '위치 권한 다시 요청'
            : '위치 권한 허용'),
  ),
```

**③ "나중에 하기" 아래 결과 안내 캡션 추가 (`:113-116` TextButton 바로 다음)**

```
확정 (TextButton 다음에 추가):
  const SizedBox(height: 4),
  Text(
    '지금 건너뛰면 위치 공유 기능을 쓸 수 없어요. '
    '나중에 홈 화면의 "위치 공유 설정"에서 언제든 다시 켤 수 있어요.',
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
  ),
```

**④ permanentlyDenied 배너 (`:88-93` 블록의 message)** — "설정 앱 열기" 버튼과 경로를 구체적으로 연결

```
현재: message: '위치 권한이 거부되어 있어요. 설정 앱에서 권한을 허용해주세요.',
확정: message: '위치 권한이 꺼져 있어요. 아래 "설정 앱 열기"를 눌러 권한 > 위치를 허용해주세요.',
```

**⑤ serviceDisabled 배너 (`:77-81` 블록의 message)** — 소폭 명확화(선택 반영)

```
현재: message: '기기의 위치 서비스가 꺼져 있어요. 설정에서 켜주세요.',
확정: message: '기기의 위치 서비스가 꺼져 있어요. 아래 "위치 서비스 설정 열기"에서 위치를 켜주세요.',
```

이 다섯 배너/라벨 문구는 서로 "아래 OO 버튼" 형태로 바로 밑 버튼 라벨을
그대로 인용하도록 맞춰 놨다 — 버튼 라벨을 바꾸면 배너 문구의 인용도 같이
맞춰야 한다.

### P2-6. "추방" → "내보내기" 어휘 순화 — 확정 (이번 커밋 포함, Plexa 승인 2026-08-27)

**파일**: `app/lib/features/relationships/presentation/screens/group_detail_screen.dart`

"추방"은 커플·가족·친구 대상 앱 톤에 거칠다. 문자열 하나짜리 변경이고
이 파일은 이번 라운드에 이미 열려 있으므로 이번 커밋에 포함한다. 확인 문구
(`:115` `'${member.nickname}님을 그룹에서 내보낼까요?'`)는 이미 "내보내기"
어휘라 그대로 두고, 아래 3곳만 바꾼다.

```
group_detail_screen.dart:114
  현재: title: '멤버 추방',
  확정: title: '멤버 내보내기',

group_detail_screen.dart:116
  현재: confirmLabel: '추방',
  확정: confirmLabel: '내보내기',

group_detail_screen.dart:270
  현재: tooltip: '추방',
  확정: tooltip: '내보내기',
```

`:130` 스낵바 폴백 문구(`'멤버 추방 중 문제가 발생했습니다…'` → `'멤버를
내보내지 못했어요. 다시 시도해주세요.'`)는 P2-1 표에도, P0-7 쓰기 경로
`fallback:` 인자에도 등장한다 — 세 곳의 최종 문자열을 동일하게 맞춘다.

> **참고**: `_removeMember`의 `on PostgrestException` 원문 노출은 처음에
> 이 한 곳(`:128`)만 발견했으나, Plexa가 전수 grep으로 같은 파일 `:65`
> (`_createInvitation`)·`:149`(`_leaveGroup`)까지 3곳임을 확인해 **P0-7
> 쓰기 경로**로 편입했다(위 P0-7 참고). `group_list_screen.dart`에는 같은
> 패턴 없음.

### Diana 적용 순서 제안

1. **P1-7** (4곳) + **P2-5** (변경 없음, 확인만) — 위치 설정 화면 한 파일 위주.
2. **P1-4** (권한 화면 한 파일 — 배너 3개 + 버튼 라벨 1 + "나중에 하기" 캡션 1).
3. **P2-1** 표 + **P2-6** (3곳) — 파일별로 위→아래 치환. 카피·톤 커밋(커밋A)
   하나로 묶어도 됨.
4. **P0-7** (읽기 경로 3곳 + 쓰기 경로 3곳 = 6곳) — **별도 커밋B**로 분리
   (위 P0-7 참고). 포함: 공용 모듈 `server_error_message.dart` 신설, 도메인
   데이터 2개(`shareSettingsServerErrors` / `relationshipGroupServerErrors`),
   기존 `_mapShareErrorMessage`(P0-5)를 공용 함수 호출로 이관, 쓰기 3곳 +
   읽기 3곳 교체. 커밋A와 `group_detail_screen.dart`의 폴백 문자열이 겹치므로,
   두 커밋 중 나중 것에서 최종 문자열이 표와 일치하는지 확인.

적용 후 최종 확인:
- `grep -rn "습니다\|합니다\|됩니다\|수집\|전송\|추방" app/lib`로 사용자 문구에
  합쇼체·내부용어가 남지 않았는지 스캔(개발자 로그·Exception 메시지 제외).
- `grep -rn "_showSnackBar(e.message)\|\${snapshot.error}" app/lib`로 P0-7
  6곳이 모두 없어졌는지 확인.
