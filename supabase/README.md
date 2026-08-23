# 곁에(Gyeote) — Supabase 백엔드

Phase 0 (부트스트랩) 범위: 인증 기반(profiles) + 관계 모델(관계 그룹/멤버십/초대).
Phase 1 (이번 라운드) 범위: 위치 공유(PostGIS 좌표, 그룹별 공유 모드, 실시간
브로드캐스트). 사진/미디어, 버킷리스트 데이터 모델, 실시간 동시 편집 동기화는
다음 라운드에서 이 위에 추가한다.

## 구조

```
supabase/
  config.toml              # Supabase CLI 로컬 프로젝트 설정 (db major_version = 17)
  migrations/
    20260820090001_extensions.sql            # pgcrypto 확장 활성화
    20260820090002_profiles.sql              # profiles 테이블 + RLS + auth.users 트리거
    20260820090003_relationship_groups.sql   # relationship_groups 테이블
    20260820090004_relationship_members.sql  # relationship_members 테이블 + RLS 헬퍼 함수
    20260820090005_relationship_invitations.sql # relationship_invitations 테이블 + RLS
    20260820090006_relationship_functions.sql   # 그룹 생성/초대/수락/탈퇴 RPC 함수
    20260820090007_location_extensions.sql   # postgis 확장 활성화
    20260820090008_location_share_settings.sql # 그룹별 위치 공유 모드/일시중지 설정
    20260820090009_user_locations.sql        # 최신 위치 1행 + RLS(이 라운드의 보안 핵심)
    20260820090010_location_history.sql      # 위치 이력 + 보존기간 정리 함수
    20260820090011_location_functions.sql    # 위치 핑 업서트/공유모드 설정/피어 조회 RPC
    20260820090012_location_realtime.sql     # Realtime Broadcast + Authorization
    20260823100002_fix_location_spoofing_and_scope_bypass.sql # 위치 스푸핑/그룹 접근범위 우회 차단
```

로컬 개발 시 (Docker 필요):

```bash
npx supabase start   # 로컬 Postgres + Auth + Realtime + Studio 기동
npx supabase db reset  # migrations/ 순서대로 재적용
```

## 스키마 개요

### 1. `public.profiles`
- `auth.users`와 1:1 매핑되는 공개 프로필(닉네임, 아바타 URL).
- `auth.users` insert 시 `handle_new_user()` 트리거가 자동으로 row를 생성한다.
- RLS: 로그인한 모든 사용자가 조회 가능(최소 공개 정보만 포함), 본인만 수정 가능.

### 2. 관계 모델 (커플 / 가족 / 친구)

| 테이블 | 역할 |
|---|---|
| `relationship_groups` | 관계 그룹 자체. `type` = `couple` \| `family` \| `friend` |
| `relationship_members` | 그룹-사용자 매핑. `role` = `owner` \| `member` |
| `relationship_invitations` | 초대 코드/링크와 상태(`pending`/`accepted`/`expired`/`revoked`) |

**쓰기 경로가 RPC로 제한되는 이유**: 그룹 생성(그룹 row + owner 멤버십), 초대
수락(멤버십 추가 + 초대 상태 갱신) 등은 여러 행에 걸친 원자적 처리와 추가 권한
검증이 필요하다. 따라서 `relationship_members`, `relationship_invitations`에는
클라이언트가 직접 쓸 수 있는 INSERT/UPDATE RLS 정책을 두지 않고, 아래
`SECURITY DEFINER` RPC 함수를 통해서만 쓰기를 허용한다. (SELECT는 RLS로
읽기 범위를 제한한다.)

| 함수 | 설명 |
|---|---|
| `create_relationship_group(type, name)` | 그룹 생성 + 생성자를 owner로 등록 |
| `create_relationship_invitation(group_id, invited_email?)` | 그룹 멤버가 초대 생성 |
| `get_invitation_preview(invite_code)` | 미가입 상태에서 초대 코드로 그룹 정보 미리보기(최소 정보) |
| `accept_relationship_invitation(invite_code)` | 초대 수락 → 멤버십 추가 + 초대 상태를 `accepted`로 갱신 |
| `revoke_relationship_invitation(invitation_id)` | 초대자 또는 owner가 대기 중인 초대 취소 |
| `leave_relationship_group(group_id)` | 본인 탈퇴. 마지막 멤버였다면 그룹 자체도 삭제(빈 그룹 방지) |
| `remove_relationship_member(group_id, user_id)` | owner가 다른 멤버를 추방 |

**RLS 요약**
- `relationship_groups` / `relationship_members`: 본인이 속한 그룹만 SELECT 가능
  (`is_group_member()` / `is_group_owner()` security-definer 헬퍼로 순환 참조 없이 판별).
- `relationship_groups`: UPDATE(이름 변경)/DELETE는 owner만.
- `relationship_invitations`: SELECT는 그룹 멤버 또는 수락한 본인만.
- **하위 데이터 정리**: `relationship_members`, `relationship_invitations`의
  `group_id`는 `on delete cascade`이므로 그룹 삭제 시 멤버십/초대가 자동 정리된다.
  마지막 멤버가 탈퇴하면 `leave_relationship_group()`이 빈 그룹을 자동 삭제한다.

## 3. 위치 공유 (Phase 1)

### 테이블

| 테이블 | 역할 |
|---|---|
| `location_share_settings` | 사용자별/관계 그룹별 위치 공유 모드(`off`/`precise`/`approx`) + 일시중지(`paused_until`) 설정 |
| `user_locations` | 사용자당 최신 위치 1행(UPSERT 대상). `location geography(Point,4326)`, 정확도, 배터리, 이동 상태, 측정/수신 시각 |
| `location_history` | 위치 이동 이력(경로 재생용 원시 데이터). 보존기간 경과 후 정리 대상 |

**PostGIS**: `extensions` 스키마에 설치(`pgcrypto`와 동일 컨벤션). 좌표는
`geography(Point, 4326)`으로 저장해 지구 곡률을 고려한 정확한 거리 계산이
가능하도록 했다.

### 공유 모드와 일시중지의 의미
- `mode = off`: 해당 그룹에는 위치를 전혀 공유하지 않음. **완전 OFF(모든 그룹이
  off)이면 서버는 위치 저장 자체를 거부**한다(불필요한 개인정보 보관 최소화).
- `mode = precise` / `approx`: 그룹에 위치를 공유하되, `approx`는 좌표를 약
  100m 격자(0.001도 ≈ 111m, `ST_SnapToGrid`)로 서버가 강제 반올림해서만
  노출한다. 정확도(`accuracy_m`)도 함께 숨긴다(정밀도 하향이 클라이언트가
  아니라 서버에서 강제되어야 우회 불가능).
- `paused_until`: "N분만 임시로 끄기" 같은 **일시중지 만료 시각**. `mode`는
  그대로 두고 특정 시점까지만 가시성을 끈다. **일시중지는 가시성(RLS)에만
  영향을 주고, 저장 여부(위치 핑 수락/삭제)에는 영향을 주지 않는다** — 그래야
  일시중지가 끝나는 즉시 새 GPS fix를 기다리지 않고 마지막 위치가 다시
  노출된다. 반대로 `mode = off`로 전환하면(모든 그룹이 off가 될 때) 저장된
  최신 위치를 즉시 삭제한다.
  - 로컬 검증 중 초기 구현에서 `paused_until is null or paused_until > now()`
    조건으로 "일시중지 중에도 보임"이 되는 부호 반전 버그를 발견해
    `paused_until is null or paused_until <= now()`(일시중지가 지났을 때만
    보임)로 수정했다. 아래 검증 시나리오 참고.

### RPC 함수 (프론트엔드가 호출할 인터페이스)

| 함수 | 설명 |
|---|---|
| `set_location_share_mode(relationship_group_id, mode, pause_minutes default null)` | 그룹별 공유 모드 설정. 그룹 멤버만 호출 가능. 모든 그룹이 `off`가 되는 순간에만 `user_locations`의 본인 행을 삭제 |
| `upsert_location_ping(location, accuracy_m, battery_level, is_charging, movement_state, captured_at)` | 본인 위치 핑 업서트 + `location_history`에 적재. 모든 그룹이 `off`면 거부. `captured_at`이 기존 저장값보다 과거면 무시(오프라인 큐 역행 방지) |
| `get_peer_locations(relationship_group_id)` | 호출자가 실제 멤버인 그룹에서만 조회 가능(비멤버가 호출하면 빈 결과). 그룹 내 RLS상 조회 가능한 상대들의 최신 위치. `approx` 상대는 좌표를 약 100m 격자로 반올림, `accuracy_m`은 숨김 |
| `get_share_mode(owner_id, relationship_group_id)` | (내부용 헬퍼, 필요 시 클라이언트도 호출 가능) 호출자가 이미 볼 권한이 있거나 본인 자신을 조회하는 경우에만 모드를 반환 — 임의 사용자의 공유 여부를 알아내는 경로 차단 |
| `delete_expired_location_history(retention_days default 14)` | 보존기간 경과 이력 삭제. **`service_role` 전용**(일반 사용자 호출 불가). pg_cron 또는 외부 스케줄러로 주기 실행 필요(이 저장소에는 스케줄 등록을 포함하지 않음) |

### RLS 요약 (이 라운드의 보안 핵심)
- `location_share_settings`: 본인 행만 SELECT 가능. 쓰기는 `set_location_share_mode()` RPC로만.
- `user_locations`:
  1. 본인 행은 항상 SELECT 가능.
  2. 타인의 행은 `can_view_location(owner_id, viewer_id)` (SECURITY DEFINER
     헬퍼)가 true일 때만 SELECT 가능 — "같은 관계 그룹에 속해 있고 AND 그
     그룹에서 owner의 `mode <> 'off'`이고 AND (`paused_until`이 null이거나
     이미 지났음)"인 경우.
  3. 쓰기는 전혀 허용하지 않음(`upsert_location_ping()` / `set_location_share_mode()` RPC로만).
  - **알려진 한계**: `user_locations`는 사용자당 1행이라 group_id를 갖지
    않는다. 따라서 두 사용자가 동시에 여러 관계 그룹에 속해 있고 그 중 한
    그룹만 `off`로 꺼둔 경우, 다른 그룹이 활성 상태라면 여전히 조회 가능하다
    (그 그룹 맥락에서는 정상 동작). 동일 두 사용자가 여러 그룹에 동시 소속되는
    경우는 드물지만 인지하고 있어야 한다.
- `location_history`: 본인 이력만 SELECT 가능(상대 그룹원에게도 노출하지 않음 — 과거 경로는 실시간 스냅샷보다 더 민감할 수 있다는 판단).

### Realtime Broadcast
- `upsert_location_ping()`이 저장을 마친 뒤 `notify_location_ping()`을 호출해
  `relationship:{group_id}:location` 토픽으로 `realtime.send(payload, 'location_update', topic, true)`
  (Supabase Broadcast from Database)를 통해 변경을 전파한다. `approx` 그룹에는
  브로드캐스트 payload의 좌표도 동일하게 격자 반올림해서 내보낸다(실시간
  채널로도 정밀 좌표가 새지 않도록).
- `realtime` 스키마는 실제 Supabase 플랫폼에만 존재하므로, `notify_location_ping()`과
  `realtime.messages` RLS 정책 생성 모두 **런타임/마이그레이션 시점에 `realtime`
  스키마 존재 여부를 확인 후 없으면 조용히 건너뛰도록** 방어적으로 작성했다
  (순수 로컬 Postgres에서도 마이그레이션 전체가 에러 없이 적용됨 — 이번 라운드
  검증 환경이 Docker 없는 로컬 PostgreSQL 14 + PostGIS였기 때문). **이 부분은
  Docker가 있는 실제 Supabase 로컬 스택(`npx supabase start`)에서 브로드캐스트가
  실제로 도달하는지 별도로 재검증이 필요하다.**
- **Realtime Authorization(중요)**: `relationship:{group_id}:location` 채널은
  반드시 **Private 채널**로 구독해야 한다(클라이언트:
  `supabase.channel(topic, { config: { private: true } })`). 이 마이그레이션은
  `realtime.messages`에 "그룹 멤버만 해당 topic을 SELECT 가능"한 RLS 정책을
  건다. 이 정책이 없으면 인증된 사용자 누구나 임의의 관계 그룹 topic을
  구독해 도청할 수 있으므로 반드시 필요하다.
- **대안(폴백)**: 만약 Broadcast 설정에 문제가 있거나 당장 검증이 어렵다면,
  클라이언트가 `postgres_changes`로 `user_locations` 테이블 변경을 구독하는
  방식도 사용할 수 있다. 이 경우에도 Supabase Realtime의 RLS 기반 필터링이
  적용되므로 `user_locations`의 SELECT RLS 정책이 그대로 도청 방지 역할을 한다.

### 로컬 검증 방법 및 확인한 시나리오
Docker 없이 로컬 PostgreSQL 14 + `postgresql-14-postgis-3` 패키지를 설치하고,
`auth.users`/`auth.uid()`를 최소 스텁으로 구성한 뒤 `authenticated` 롤로
`SET request.jwt.claim.sub = '<uuid>'`를 사용해 사용자를 impersonate하여
Phase 0+1 마이그레이션 전체를 순서대로 적용하고 검증했다. 확인한 시나리오:

1. 공유가 완전 OFF(모든 그룹에서 off)인 상태에서 `upsert_location_ping()` 호출 → 거부됨.
2. 그룹에서 `mode='precise'`로 켠 뒤 위치 전송 → 관계 있는 상대(alice)는 조회
   가능, 관계 없는 사용자(carol)는 조회 불가(0 rows).
3. 그룹에서 `mode='off'`로 전환(유일한 그룹) → `user_locations` 본인 행이
   즉시 삭제됨.
4. `mode='precise'` + `pause_minutes=5`로 일시중지 → 상대방 조회 즉시 차단(0
   rows), 그러나 저장된 행 자체는 삭제되지 않음. `paused_until`을 과거로
   되돌리면(만료 시뮬레이션) 새 핑 없이도 즉시 다시 조회 가능해짐.
5. `mode='approx'`로 정밀 좌표(127.00034, 37.50021) 전송 → `get_peer_locations()`
   가 좌표를 (127, 37.5)로 반올림하고 `accuracy_m`을 숨겨서 반환.
6. 기존 저장된 `captured_at`보다 과거인 위치 핑 전송(오프라인 큐 역행 시나리오)
   → 무시되고 기존 최신 행이 그대로 반환됨. 반대로 더 최신 `captured_at`
   핑은 정상 반영됨.
7. `location_history`에 핑마다 이력이 쌓이고, 본인만 조회 가능(타인은 0
   rows). `delete_expired_location_history()`는 `service_role`만 실행
   가능(일반 `authenticated` 호출 시 permission denied), 보존기간 경과 행만
   삭제됨을 확인.
8. `get_share_mode()`를 관계/권한 없는 사용자가 직접 호출해도 `null` 반환(정보
   유출 방지 가드 동작 확인). `user_locations`/`location_share_settings`에
   대한 직접 INSERT/UPDATE는 `authenticated` 롤에 grant가 없어 permission
   denied로 차단됨을 확인.

## 다음 라운드에서 이어서 할 일 (이번 라운드 범위 아님)
- 사진/미디어 저장(Storage 버킷 + RLS), 버킷리스트 데이터 모델, 실시간 동시
  편집 동기화.
- 지오펜스/도착 알림 등 위치 기반 확장 기능(이번 라운드 범위 밖).
- `location_history` 보존기간 정리 함수(`delete_expired_location_history()`)의
  실제 스케줄 등록(pg_cron 또는 외부 스케줄러).
- Realtime Broadcast가 실제 Supabase 로컬 스택(Docker)에서 의도대로 동작하는지
  재검증.
