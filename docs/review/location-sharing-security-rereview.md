# 위치 공유 보안 수정 재검토 (Rena, 2026-08-23 ~ 2026-08-24)

대상: `supabase/migrations/20260823100001_fix_invitation_email_check.sql`,
`20260823100002_fix_location_spoofing_and_scope_bypass.sql`,
`20260823100003_fix_location_ping_input_validation.sql`,
그리고 이 세 마이그레이션이 촉발한 프론트 에러 노출 경로 검토
(`app/lib/features/location/map/location_map_screen.dart`,
`app/lib/features/location/settings/share_settings_screen.dart`,
`app/lib/features/location/collector/location_collector_service.dart`).

이 문서는 라운드가 진행되며 발견 순서대로 쌓인 기록이다 — 아래 각 섹션은 발견 당시 시점의
상태를 담고 있고("아직 미수정"이라고 쓰인 부분이 있음), **최종 상태는 이 문단과 바로 아래
"결론 요약"만 최신이다.**

## 최종 상태 (2026-08-24 기준)

이 시점까지 확인한 바로 아래 세 마이그레이션 전부 커밋됐다:
`26e3bed`(HIGH-1/HIGH-2 + 재리뷰 A/B/C), `99bef0b`(초대 이메일 검증), `5c77b96`(accuracy_m/
battery_level 입력 검증). 이어서 프론트 P0 6건(`75dd721`)과 후속 수정/리팩터링
(`a0fb944`, `b8a4e8e`, `2c42820`, `d4909a0`)도 커밋됐다. 이 문서에서 지적한 항목 중:

- HIGH-1/HIGH-2/A(get_share_mode 그룹경계)/B(off·미설정 유출)/C(일시중지 그룹별 미적용) —
  전부 코드 레벨로 수정 확인·검증 완료(아래 각 섹션 참고).
- E(accuracy_m/battery_level 검증 누락, P0-4 원문 노출) — 수정 확인·검증 완료(100003 섹션).
- `is_location_paused`의 행-존재-여부 오라클 — 검토 결과 **별도 수정 불필요**로 결론(해당 섹션
  참고), 다음 라운드에 `get_share_mode`와 게이팅을 함께 재검토하는 티켓으로 이관.
- `supabase/tests/database/location_sharing_security.test.sql`이 신설되어 위 6건
  (HIGH-1/HIGH-2/A/B/C/E, 파일 내 라벨은 각각 다름)을 커버하는 14개 케이스를 담고 있다 —
  케이스 구성을 코드로 대조해 시나리오 설계 자체는 검증했다(그룹 경계/크로스그룹 RLS를
  피하도록 픽스처가 짜여 있어 "우연히 통과"가 아니라 실제 로직을 검증하는 구조임을 확인).
  **다만 이 문서를 쓰는 시점에 최종 재실행의 PASS/FAIL 원문 출력을 내가 직접 확인하지는
  못했다** — Tom의 테스트 커밋 메시지에 실행 방법과 결과가 남는다고 들었으니 그쪽을 근거로
  삼을 것. 기존 `location_sharing.test.sql`의 "미실행" 표기는 의도적으로 그대로 유지됐다(실행
  안 된 걸 실행된 것처럼 보이지 않게 하려는 목적 — 새 `location_sharing_security.test.sql`이
  이를 대체/보강하는 별도 파일).
- 프론트: `flutter analyze` 에러 0/info 6, `flutter test` 36/36 통과(Plexa 보고 기준).

**문서 커밋 판단(Din 요청):** 위 내용 기준으로 이 상태 그대로 커밋해도 좋다. 아래 본문은 시점별
기록으로 그대로 두는 것이 맞다(어떻게 문제를 발견하고 좁혀갔는지가 남아야 다음에 같은 실수를
피하기 쉽다) — 다만 상단에 이 "최종 상태" 요약을 추가해 문서 앞부분만 보는 사람이 이미 해결된
항목을 미해결로 오인하지 않도록 했다.

---

## (1) HIGH-1 / HIGH-2가 실제로 닫혔는가

**HIGH-1 (스푸핑) — 닫힘.**
`notify_location_ping()`에 `p_location.user_id is distinct from auth.uid()` 재검증을 추가하고,
`revoke execute ... from authenticated`로 클라이언트의 직접 RPC 호출 경로를 막았다.
`upsert_location_ping()`은 여전히 내부에서 `notify_location_ping()`을 호출할 수 있는데, 이는
**SECURITY DEFINER 함수가 다른 함수를 호출할 때 실행 권한 체크가 호출 체인의 "정의자(owner)"
기준으로 이뤄지기 때문**이다(nested SECURITY DEFINER 호출에서 `current_user`가 outer 함수
owner로 바뀜) — `authenticated`에서 EXECUTE를 회수해도 owner/슈퍼유저의 암묵적 권한에는
영향이 없으므로 내부 호출 경로는 그대로 살아있고, 클라이언트발 직접 RPC 호출만 차단된다.
의도대로 동작한다. 이중 방어(auth.uid() 재검증)까지 있으니 grant 실수로 다시 열려도 스푸핑은
막힌다.

**HIGH-2 (get_peer_locations 접근범위 우회) — 닫힘.**
`join relationship_members rm on rm.user_id = ul.user_id and rm.group_id = p_relationship_group_id`
로 "대상이 그 그룹의 멤버"를 걸고, `where ... and public.is_group_member(p_relationship_group_id, auth.uid())`
로 "호출자도 그 그룹의 멤버"를 건다. 두 조건이 함께 있어야 행이 나오므로, 호출자가 속하지 않은
임의의 `group_id`를 넣는 시나리오는 `is_group_member`에서 걸러진다. `set_location_share_mode()`가
쓰기 경로에서 쓰는 것과 동일한 패턴이라 일관성도 맞다.

## (2) CREATE OR REPLACE로 인한 속성/권한 유실 여부

없음. 세 함수(`notify_location_ping`, `get_peer_locations`, `accept_relationship_invitation`) 모두
- 시그니처(인자 타입) 불변 → OID/오너십 유지됨.
- `language`/`security definer`/`stable`/`set search_path` 등 속성이 원본과 동일하게 재선언됨.
- 권한(GRANT/REVOKE)은 CREATE OR REPLACE로 자동 초기화되지 않는다는 점을 이용해, `100002`가
  `notify_location_ping`에 대해서만 명시적으로 `revoke execute ... from authenticated`를 추가하고
  (기존 090012의 grant를 명시적으로 되돌림), `get_peer_locations`는 기존과 동일한 grant를
  재선언(변경 없음)했다 — 의도대로다.
- `accept_relationship_invitation`(100001)은 grant/revoke 문을 아예 반복하지 않는데, 이는
  CREATE OR REPLACE가 기존 ACL을 보존하기 때문에 문제 없다(090006에서 준 `authenticated` grant가
  그대로 유지됨). 확인 완료.

## (3) get_share_mode: HIGH-2와 같은 종류의 구멍이 남아있음 — **커밋 전 수정 권장**

`get_share_mode(p_owner_id, p_relationship_group_id)`는 이번 두 마이그레이션에서 전혀 손대지
않았고, 여전히 `authenticated`에 직접 EXECUTE가 부여된 RPC다(090011). 이 함수는
`get_peer_locations()`처럼 "호출자가 `p_relationship_group_id`의 멤버인지"를 확인하지 않고,
`p_owner_id = auth.uid() or can_view_location(p_owner_id, auth.uid())`만 확인한다.
`can_view_location`은 "호출자와 대상이 **어떤 그룹에서든** 활성 공유 중이면" true를 반환하는
크로스-그룹 판별이다(user_locations RLS와 동일한 헬퍼).

결과적으로: 호출자가 피해자와 그룹 A에서만 활성 공유 중이더라도, `get_share_mode(피해자,
그룹B)`를 직접 RPC로 호출하면 — 호출자가 그룹 B의 멤버가 전혀 아니어도 — 피해자가 그룹 B에
대해 `location_share_settings` 행을 갖고 있는지(＝사실상 그룹 B의 멤버였는지) 와 그 모드값을
알아낼 수 있다. `get_peer_locations()`는 이번에 막았지만 **형제 함수인 `get_share_mode()`는
동일한 종류의 그룹 경계 우회 오라클로 남아있다.**

권장 수정: `get_share_mode`의 WHERE 절에도
`and public.is_group_member(p_relationship_group_id, auth.uid())`를 추가한다(HIGH-2와 동일 패턴).
단, `get_peer_locations`가 이 함수를 내부에서 호출하므로 — `get_peer_locations`는 INVOKER 함수라
`get_share_mode` 호출 시 "실제 호출자(authenticated)" 권한으로 실행됨 — 이 함수의 EXECUTE
grant 자체는 유지해야 한다(notify_location_ping처럼 revoke로 닫을 수 없음). 로직 안쪽에서
멤버십을 검증하는 방식으로 가야 한다.

## (3-부속) 예외 vs 빈 결과: get_peer_locations의 현재 방식이 맞다

`get_peer_locations`는 비멤버 호출 시 예외 없이 **빈 결과셋**을 반환한다. 이건 좋은 설계다 —
예외를 던지면 "그룹이 존재하지 않음"과 "그룹은 있지만 멤버가 아님"을 구분할 오라클이 생길 수
있는데, 빈 결과는 둘을 구분 불가능하게 만든다. `get_share_mode`에 멤버십 체크를 추가할 때도
**예외가 아니라 NULL을 반환**하도록 해야 기존 관례와 일관되고 오라클이 새로 생기지 않는다
(`set_location_share_mode`가 예외를 던지는 건 "내가 속한 그룹의 설정을 바꾸려는 자기 자신의
요청"이라 다른 문맥이라 그대로 둬도 무방).

## (2-확장) get_peer_locations CASE 분기: 'off' 또는 설정 없음 → 정밀 좌표 유출 (기존 버그, 이번에 만진 함수)

이번 수정과 무관하게 원래부터 있던 문제인데, 이번 마이그레이션이 같은 함수를 다시 정의하므로
같이 보고한다. CASE 분기가 `= 'approx'`만 특별 처리하고 나머지는 전부 `else ul.location`
(정밀 좌표)로 떨어진다:

```sql
case
  when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then ...반올림...
  else ul.location
end as location
```

`get_share_mode`가 'off'를 반환하거나(해당 그룹에 대한 공유 모드를 명시적으로 껐음) 아예 NULL을
반환하는(해당 그룹에 대한 `location_share_settings` 행 자체가 없음) 두 경우 모두 "정밀 좌표
그대로"로 처리된다. RLS(`can_view_location`)는 "어떤 그룹에서든 활성 공유 중이면 통과"이므로,
피해자가 그룹 G1에서는 OFF, 그룹 G2에서는 공유 중이라면, 같은 두 사용자 사이에서 G1 컨텍스트로
`get_peer_locations(G1)`을 호출해도 (G2 덕에 RLS는 통과) G1에서 OFF로 꺼둔 사람의 정밀 좌표가
그대로 노출된다. "이 그룹에서는 안 보이게 껐다"는 사용자 기대와 어긋난다.

권장 수정: `else` 분기를 'precise'일 때만 원본으로, 그 외(off/null)는 결과에서 제외하거나
location/accuracy_m을 null로 강제.
```sql
where ... and public.get_share_mode(ul.user_id, p_relationship_group_id) in ('precise', 'approx')
```
같은 조건을 WHERE에 추가하는 편이 CASE 세 곳을 다 고치는 것보다 간단하다.

## README 문서 갭

`supabase/README.md`의 마이그레이션 목록에 `20260823100001`만 추가되고 `20260823100002`가
빠져 있다 — Plexa가 이미 인지하고 커밋 분리 지시를 낸 것으로 보인다(중복 보고 아님, 확인만).

## Tom 테스트 실행 여부

`supabase/tests/database/location_sharing.test.sql` 파일 상단에 "이번 QA 라운드에서 실제로
실행/검증되지 못했다"고 명시돼 있다(샌드박스에 Docker/Supabase CLI 없음). 즉 HIGH-1/HIGH-2/
초대 이메일 수정 모두 **문법조차 실제 DB에 대해 확인된 적이 없다.** 로컬 Supabase 스택이 있는
환경에서 `supabase test db` 1회 실행이 커밋 전 필수. 추가로 회귀 테스트에 다음 케이스를 넣을
것을 제안한다:
- (신규 요청됨) HIGH-2: 비멤버가 남의 group_id로 `get_peer_locations` 호출 시 빈 결과.
- **get_share_mode 직접 호출 오라클**: 그룹 B에 속하지 않은 사용자가 (그룹 A에서는 활성 공유
  중인) 상대의 `get_share_mode(상대, 그룹B)`를 호출했을 때 NULL이어야 함(수정 후).
- **다중 그룹 off 유출**: 같은 두 사용자가 그룹 G1(off)/G2(active) 양쪽에 속할 때,
  `get_peer_locations(G1)`이 정밀 좌표를 반환하면 안 됨(현재는 반환됨 — 수정 필요 항목의 회귀
  테스트로 미리 작성 권장).
- notify_location_ping 직접 RPC 호출 시 `permission denied`로 거부되는지(42501).

## 추가 라운드: Dexa의 (A)(B)(C) 수정 최종 검증

`20260823100002_fix_location_spoofing_and_scope_bypass.sql`에 반영된 세 건 모두 코드를 다시
읽고 검증했다.

**(A) `get_share_mode`에 `is_group_member(p_relationship_group_id, auth.uid())` 추가.**
정상 동작한다. 예외가 아니라 NULL을 반환하는 방식이라 `get_peer_locations`의 "빈 결과/조용한
제외" 관례와 일관되고, 오라클을 새로 만들지 않는다.

> **주의 — 이 멤버십 체크를 "중복이니 제거해도 된다"고 오해하지 말 것.** `get_share_mode`는
> `authenticated`에 직접 EXECUTE 권한이 부여된 독립 RPC로, 클라이언트가 `get_peer_locations`를
> 거치지 않고 곧바로 호출할 수 있다. `get_peer_locations` 문맥 안에서만 보면 이 함수 자신의
> `where`에 있는 `is_group_member(p_relationship_group_id, auth.uid())`가 이미
> `get_peer_locations`의 WHERE 절에 있는 동일한 체크와 겹쳐 보이지만, 그건 어디까지나
> `get_peer_locations`를 경유하는 한 경로에서만 그렇다. **클라이언트가 `get_share_mode`를
> 직접 RPC로 호출하는 경로에서는 이 체크가 유일한 방어선이다** — 애초에 (A)로 잡은 문제 자체가
> 바로 이 직접 호출 경로였다. 이 줄을 "중복 정리" 명목으로 걷어내면 (A)가 그대로 되살아난다.
> `get_share_mode` 함수 정의부와 주석에 이 취지를 남겨, 이후 리팩터링 시 실수로 제거되지 않게
> 해야 한다.

**(B) WHERE에 `get_share_mode(...) in ('precise', 'approx')` 추가.** 정상 동작한다.
`get_peer_locations`의 WHERE가 이미 호출자 멤버십을 확정한 뒤에 이 조건을 평가하므로, `X in
(...)`가 `X`가 NULL일 때 UNKNOWN으로 평가되어 해당 행이 정상적으로 제외된다. WHERE를 통과한
행만 CASE에 도달하므로, CASE의 `else` 분기(정밀 좌표)는 이제 mode가 실제로 'precise'인 경우에만
실행된다 — off/NULL이 else로 새던 원래 버그가 막혔다.

**(A)+(B) 상호작용 재검증.** `get_peer_locations`는 INVOKER라 `auth.uid()`가 실제 호출자와
같고, 같은 WHERE 절에 자체적인 `is_group_member` 체크도 있다. `is_group_member()`는 단순
존재 확인이라 크로스그룹으로 새는 지점이 없어, 두 수정이 겹쳐서 생기는 새 구멍은 찾지 못했다.

**(C) 신규 헬퍼 `is_location_paused` + WHERE에 `not coalesce(is_location_paused(...), true)`
추가(Plexa 재확인 지적).** 지적한 문제 자체가 실재한다: `get_share_mode`는 `mode` 컬럼만 보고
`paused_until`을 보지 않으므로, "G1에서 일시중지 + G2에서 활성 공유"인 상대에 대해
`get_peer_locations(G1)`이 (RLS는 G2 덕에 통과) 일시중지된 정밀 좌표를 그대로 반환했다.
`notify_location_ping`의 브로드캐스트 루프는 그룹별로 `paused_until`을 검사해 이미 이 문제가
없었으므로, 읽기 경로와 브로드캐스트 경로가 어긋나 있었던 것도 정확한 진단이다. 수정 로직도
검증했다: `is_location_paused`는 `get_share_mode`와 동일한 멤버십/가시성 게이팅을 쓰고, 이
게이팅이 이미 (B)의 `get_share_mode(...) in ('precise','approx')` 조건에서 성공했다는 뜻이므로
같은 행에 대해 `is_location_paused`가 NULL을 반환할 일은 없다(동일한 WHERE 구조라 같은 행이
같은 근거로 통과한다) — `coalesce(..., true)`의 "실패 시 안전 쪽 기본값" 처리는 방어적 장치일
뿐 이 경로에서 실제로 발동하지는 않는다. 부호(`not (paused_until is null or paused_until <=
now())` ≡ `paused_until is not null and paused_until > now()`)도 드모르간 법칙대로 정확하다.
세 건 모두 커밋해도 좋다고 판단한다.

**성능(get_share_mode/is_location_paused가 행당 여러 번 호출됨).** 보안 수정 커밋에 섞을 사안은
아니라고 본다. 그룹 규모가 커플/가족 단위로 작아 체감 영향이 적고, LATERAL/CTE로 한 번만
계산해 재사용하는 리팩터링은 다음 라운드 별도 티켓으로 미루는 게 맞다.

**남은 회귀 테스트 갭.** `supabase/tests/database/location_sharing.test.sql`은 이 시점까지
확인한 바로는 아직 pgTAP 원안(9개 케이스, "미실행" 명시) 그대로이고, (A)/(B)/(C)를 검증하는
새 케이스(다중 그룹 off/paused 시나리오, `get_share_mode` 직접 호출 오라클 차단)가 아직
추가되지 않았다. Tom이 순수 SQL 단언으로 재작성 중이라고 들었으니, 완료되면 위 세 시나리오가
실제로 커버되는지 이어서 확인이 필요하다.

## 100003: upsert_location_ping CREATE OR REPLACE 전문 대조

`20260823100003_fix_location_ping_input_validation.sql`이 `upsert_location_ping()`을 통째로
다시 정의하면서 옮겨 적는 과정에 누락이 생겼을 수 있다는 우려가 있어, 원본
(`20260820090011_location_functions.sql`)과 줄 단위로 대조했다.

**두 핵심 로직 모두 정확히 보존됨.**
- **프라이버시 게이트**(`v_has_active_share` 체크 → 모든 그룹이 off면
  `'location sharing is off for all groups; ...'` 예외): 조건문·주석·쿼리 전부 원본과 동일하게
  살아있다.
- **역행 방지**(`if found and v_existing.captured_at > p_captured_at then return v_existing;
  end if;`): 원본과 동일하게 살아있다.
- 그 외 `insert ... on conflict (user_id) do update set ...`, `location_history` insert,
  `perform notify_location_ping(v_result)`, `return v_result` 전부 컬럼/순서까지 원본과 동일.
- 새로 추가된 두 검증(`accuracy_m < 0`, `battery_level not between 0 and 100`)은 기존
  `movement_state`/`captured_at` 체크보다 앞쪽에 삽입됐을 뿐, 순서가 바뀌어도 각 검증이 서로
  독립적이라 기능상 문제는 없다.
- 시그니처(인자 타입/기본값)·`language plpgsql`·`security definer`·`set search_path = public`
  모두 원본과 동일 — CREATE OR REPLACE가 OID/오너십/ACL을 그대로 보존한다(100001에서 이미 확인한
  것과 동일한 패턴). 이 파일에 별도 `grant`가 없는 것도 문제 아님.
- `notify_location_ping(v_result)` 호출은 이름+시그니처로 매 실행 시점에 재해석되므로, 100002가
  먼저 적용되어 있든 나중이든 실행 시점엔 항상 최신(HIGH-1 수정 반영) 정의가 호출된다 — 마이그레이션
  순서(100001→100002→100003)와 무관하게 안전.

**새 예외 문구의 노출 경로 — Plexa가 전제한 것과 다르다.** `upsert_location_ping`은 화면이 아니라
`location_collector_service.dart`(백그라운드 수집기)에서만 호출되고, 그 호출부는:
```dart
} on Exception {
  // 네트워크 오류 등 ... _lastSentAt을 갱신하지 않으므로 다음 위치 갱신 시 다시 시도된다.
}
```
`_isAllSharesOffError`로 걸러지는 "모든 그룹 off" 케이스를 제외한 모든 예외(새로 추가된
`accuracy_m`/`battery_level` 검증 실패 포함)를 **어떤 문구도 없이 완전히 조용히 삼킨다** —
`share_settings_screen.dart`의 `_mapShareErrorMessage` 같은 화이트리스트+fallback 구조 자체가
이 경로에는 없다. 즉 "화이트리스트에 없는 문구라 일반 폴백으로 덮인다"가 아니라, **애초에 아무
문구도 표시되지 않는다** — 보안/정보노출 관점에서는 이게 오히려 가장 안전한 상태다(원문이든
폴백이든 아무것도 노출되지 않음).

다만 이건 별개로 신뢰성 문제를 하나 만든다: 이 두 새 예외는 클라이언트 버그(센서가 음수
accuracy나 100 초과 battery_level을 지속적으로 보고하는 기기 특이 케이스 등)를 가리키는데,
지금 구조에서는 로그 한 줄 없이 영구히 조용히 무시되고 `_lastSentAt`이 갱신되지 않아 매 주기마다
같은 값으로 계속 재시도만 반복한다(무한 실패 루프가 눈에 안 보이는 상태로 지속될 수 있음). 이건
보안 이슈는 아니라 이번 커밋을 막을 사안은 아니지만, `location_map_screen.dart`의 `_refresh`가
이미 쓰는 것과 같은 패턴으로 `developer.log`만이라도 추가해 진단 가능하게 해두길 권한다(사용자
화면에 표시할 필요는 없음).

## is_location_paused의 "설정 행 존재 여부" 오라클 (Plexa 지적, 2026-08-24) — 판단: 별도 수정 불필요

**진단 자체는 정확하다.** `is_location_paused`는 대상 그룹에 설정 행이 있으면 `true`/`false`,
없으면(또는 게이팅 실패 시) `NULL`을 반환한다. 게이팅(`is_group_member` + 크로스그룹
`can_view_location`)을 이미 통과할 수 있는 호출자 — 즉 피해자를 G1의 멤버로서 알고 있고, G2 등
다른 그룹에서 이미 활성 공유로 보고 있는 호출자 — 라면, `NULL` 대 `false`(또는 `true`)의 구분을
"G1에 대해 설정 행이 존재하는지"의 오라클로 쓸 수 있다는 지적은 코드와 정확히 일치한다.

다만 정확히 짚어야 할 점: `false`는 "off"와 "paused 아닌 precise/approx" 둘 다에서 동일하게
나온다(`paused_until is null or 과거`인 모든 경우가 `false`) — 즉 이 함수 자체가 직접 드러내는
건 "off인지 미설정인지"가 아니라 "G1에 대해 설정을 만진 적이 있는지"(row 존재 여부)뿐이다.

**판단 1 — 막을 값어치가 있는가: 없다고 본다. 이미 `get_share_mode`가 완전히 상위호환으로
새고 있기 때문이다.** `is_location_paused`와 `get_share_mode`는 게이팅 조건(`where s.user_id=...
and s.relationship_group_id=... and is_group_member(...) and (owner=auth.uid() or
can_view_location(...))`)이 **문자 그대로 동일**하다. 즉 어떤 (owner, group, caller) 조합에서
`is_location_paused`가 게이팅을 통과하면 `get_share_mode`도 반드시 통과하고, 그 경우
`get_share_mode`는 `is_location_paused`의 "행 존재 여부"보다 훨씬 많은 정보(실제 mode 값 —
'off'/'precise'/'approx' 자체)를 이미 그 caller에게 노출한다. `is_location_paused`만 틀어막아도
같은 caller가 `get_share_mode`를 직접 호출하면 그보다 더 많은 정보를 그대로 얻는다 — 즉
`is_location_paused`는 이미 (A)에서 받아들인 노출 경계 안에 완전히 포함되는 부분집합이라,
이것만 단독으로 닫는 건 실효가 없다. Plexa가 짚은 "심각도가 낮다"는 직관에 동의하고, 근거를
더 명확히 하면: 낮은 정도가 아니라 **이미 승인된 다른 채널(get_share_mode)이 상위호환으로 열려
있어 이 건 단독으로는 막을 실익이 없다**가 더 정확한 이유다. 클라이언트가 off/미설정을 이미
같은 중립 문구로 묶기로 한 결정과는 별개로, 서버 계약 관점에서도 우선순위가 낮다.

**판단 2 — coalesce로 NULL을 false로 누르는 방법: 권장하지 않는다.** 두 가지 이유가 있다.
1) 위에서 설명했듯 이 함수 하나만 닫아도 `get_share_mode`로 우회 가능해 실효가 없다.
2) 이 코드베이스 전반에서 "게이팅 실패 시 NULL(예외 아님)"은 (A)에서 명시적으로 세운 관례다
   (`get_share_mode`, `is_location_paused` 둘 다, 그리고 `get_peer_locations`의 "빈 결과"도
   같은 철학). `is_location_paused` 내부에서 NULL을 false로 강제하면 "게이팅 실패"와 "게이팅
   통과 + 정상 값 false"가 이 함수 하나에서만 구분 불가능해져, 다른 함수들과 다른 계약을 갖게
   된다 — 다음에 이 코드를 보는 사람이 "왜 이 함수만 관례가 다르지"에서 혼란을 겪을 여지가
   있다. 실효도 없는데 일관성만 깨는 변경이라 권장하지 않는다.

**상호작용(get_peer_locations의 `not coalesce(is_location_paused(...), true)`)에는 영향 없음.**
`get_peer_locations`의 WHERE에서 `is_location_paused`가 호출되는 시점엔 이미 앞선
`is_group_member(...)`와 `get_share_mode(...) in ('precise','approx')` 조건이 통과한 뒤다 — 이
두 조건이 통과했다는 건 정확히 같은 게이팅(`is_group_member` + `can_view_location`)이 이미
성립했다는 뜻이므로, 그 시점에 `is_location_paused`가 내부적으로 NULL을 반환할 일 자체가 없다
(같은 행을 같은 근거로 찾아낸다). 즉 `is_location_paused`의 반환 계약을 NULL 유지든 coalesce로
바꾸든 `get_peer_locations`의 동작에는 아무 차이가 없다 — 이 함수를 단독 RPC로 직접 호출하는
경로에서만 차이가 생긴다.

**결론:** 다음 라운드 티켓으로 미뤄도 좋고, 굳이 손댈 거라면 `is_location_paused` 단독이 아니라
`get_share_mode`/`is_location_paused`가 공유하는 게이팅 자체(크로스그룹 `can_view_location`을
특정 그룹 한정으로 좁힐지)를 함께 재검토하는 아키텍처 논의로 묶는 게 맞다. 지금 커밋을 막을
사안은 아니다.

## P0-4: 지도 에러 화면의 서버 메시지 노출 검토

`location_map_screen.dart`는 `PostgrestException.message`만 보조 텍스트로 노출하고 `.details`는
쓰지 않는다(좋은 선택 — DETAIL에는 "Failing row contains (...)" 같은 행 전체 데이터가 실릴 수
있음). 위치 관련 RPC들이 명시적으로 `raise exception`하는 문구들은 검토 결과 대부분 무해하다
(내부 함수명/컬럼명/제약조건명 없음, 비즈니스 용어와 사용자 입력 에코 수준).
예외 한 건: `remove_relationship_member()`의 `'use leave_relationship_group() 사용'` 메시지가
실제 함수명을 노출하지만, 위치 화면 흐름과는 무관하고 Supabase RPC 이름은 어차피 클라이언트
SDK로 공개돼 있어 보안상 의미는 없다(UX 카피 정제 대상으로만 남겨두면 됨).

**진짜 문제는 명시적 raise가 아니라, 검증 누락으로 인해 원시 Postgres 제약조건 위반 에러가
그대로 새어나갈 수 있는 경로다.** `upsert_location_ping()`은 `p_location` 타입/`movement_state`/
`captured_at`은 명시적으로 검증하지만, **`accuracy_m`(>=0)과 `battery_level`(0~100)은 검증 없이
바로 INSERT한다**(`supabase/migrations/20260820090011_location_functions.sql`). `user_locations`
테이블에는 이 두 컬럼에 CHECK 제약조건이 걸려있으므로(`20260820090009_user_locations.sql:32-33`),
클라이언트가 음수 accuracy_m이나 101 이상 battery_level을 보내면 Postgres가 다음과 같은 원시
메시지를 던지고 이게 `PostgrestException.message`로 그대로 화면까지 도달한다:

```
new row for relation "user_locations" violates check constraint "user_locations_battery_level_check"
```

**테이블명(`user_locations`)과 자동생성된 제약조건명이 사용자 화면에 노출된다.** 심각한 취약점은
아니지만(스키마 구조 추정에 아주 약간 도움이 되는 정도) Plexa가 물어본 "내부 구현 정보 노출"
기준에는 정확히 해당한다. 권장 수정: `upsert_location_ping()` 본문에 `movement_state`와 같은
패턴으로
```sql
if p_accuracy_m is not null and p_accuracy_m < 0 then
  raise exception 'accuracy_m must be non-negative';
end if;
if p_battery_level is not null and p_battery_level not between 0 and 100 then
  raise exception 'battery_level must be between 0 and 100';
end if;
```
를 INSERT 전에 추가해 애플리케이션 레벨의 깔끔한 예외로 먼저 걸러지게 한다. Din의 화이트리스트
매핑과는 별개로, 서버 쪽에서 막아두는 게 근본 수정이다.

### 추가 확인: 실제 화면 코드의 현재 방어 상태

이후 Din/Diana가 붙인 실제 구현을 코드로 다시 확인했다.

- **`location_map_screen.dart`(`_ErrorState`)는 `e.message`/`e.toString()`을 아예 참조하지
  않는다.** `SocketException`/`TimeoutException`/`AuthException`/`PostgrestException.code`만
  보고 network/authExpired/generic 세 가지 고정 한글 문구로 분류한다. 즉 `get_peer_locations`가
  어떤 원문을 던지든(현재는 `raise exception`이 없는 순수 SELECT라 원문 자체가 없지만, 앞으로
  바뀌어도) 화면에 도달할 경로가 구조적으로 없다 — P0-4는 이 화면 기준으로 충분하다.
- **`share_settings_screen.dart`의 `_mapShareErrorMessage`는 `set_location_share_mode`가 던질
  수 있는 정확히 4개 문구(`authentication required` / `not a member of this group` /
  `invalid mode:` / `pause_minutes must be a positive integer`)만 화이트리스트 매칭하고, 매칭
  실패 시 항상 고정 fallback 문구로 덮는다.** `set_location_share_mode`의 실제 `raise
  exception` 목록과 정확히 일치하는지 `20260820090011_location_functions.sql`과 대조 완료 —
  누락/과다 없음. 이 화면도 원문이 새는 경로가 없다.
- **`upsert_location_ping`(accuracy_m/battery_level 미검증 건, 위 (C) 항목과 동일)은 화면이
  아니라 `location_collector_service.dart`(백그라운드 수집기)에서만 호출된다.** 이 경로는
  현재 예외를 잡아도 UI에 아무것도 표시하지 않는다(`_isAllSharesOffError`로 걸러지는 정상
  케이스 외에는 로그도 없이 조용히 무시하고 다음 위치 갱신을 기다림). **따라서 지금 이 순간
  실제로 화면에 원문이 새는 활성 경로는 없다.** 다만 이건 "우연히 안전한" 상태에 가깝다 — 이
  RPC를 직접 호출해 결과를 보여주는 화면(예: 디버그 화면, "지금 위치 보내기" 버튼)이 나중에
  추가되면 이 위험이 그대로 되살아난다. 그리고 UI 표시 여부와 무관하게, 네트워크 레벨에서
  클라이언트로 전달되는 `PostgrestException.message` 자체에 테이블명/제약조건명이 실리는 것은
  "화면에 안 보이니 괜찮다"로 덮을 문제가 아니라 서버가 최소한의 정보만 노출해야 한다는 원칙
  문제다. 결론: **(C) 검증 추가는 여전히 하는 게 맞다** — 지금 당장 급한 UI 취약점은 아니지만,
  방어심층(defense-in-depth) 차원에서, 그리고 향후 이 RPC를 노출하는 화면이 생겼을 때를 대비해
  서버 쪽에서 막아두는 것이 화이트리스트 하나 놓치는 실수보다 안전하다.
