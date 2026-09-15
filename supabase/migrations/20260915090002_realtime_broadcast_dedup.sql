-- =============================================================================
-- 곁에(Gyeote) v0.2: Realtime 브로드캐스트 디듀프 (비용 레버, v0.1 비용 분석
-- "큰 레버" 항목)
-- -----------------------------------------------------------------------------
-- 배경: notify_location_ping()은 위치 핑 1건마다 사용자의 활성 그룹 각각에
-- realtime.send()를 호출한다. Supabase는 브로드캐스트를 "1(send) + 구독자 수"
-- 로 과금하므로(무료 티어 2M 메시지/월), 실제로 거의 움직이지 않았거나 직전
-- 브로드캐스트로부터 얼마 지나지 않은 핑까지 매번 새로 브로드캐스트하면
-- 무료 티어를 불필요하게 빨리 태운다(docs/review 비용 분석 참고).
--
-- 이 마이그레이션이 하는 일:
--   1) 직전 브로드캐스트 대비 "충분히 안 움직였고 AND 충분히 시간이 안
--      지났으면" 이번 핑의 realtime.send()만 건너뛴다(저장은 건드리지
--      않는다 — user_locations/location_history 쓰기는 upsert_location_ping()
--      에서 이미 끝난 뒤다. 디듀프는 순전히 브로드캐스트 여부만 결정한다).
--   2) 임계값(거리/시간)을 코드에 박지 않고 별도 테이블(아래 튜닝 표)에 둬서,
--      비공개 테스트 실측치가 나오면 UPDATE 한 줄로 교정 가능하게 한다
--      (재배포/마이그레이션 불필요).
--   3) (user, group)별 "직전 브로드캐스트" 상태와, 나중에 실측 교정 근거로
--      쓸 skip/send 횟수를 별도 내부 테이블에 저장한다(클라이언트에는 어떤
--      권한도 주지 않음 — notify_location_ping() 내부에서만 읽고 쓴다).
--
-- ── 임계값을 "어떻게" 정했는가 (초기값, 추측이 아니라 근거가 있는 추정) ──
--   min_distance_m = 15:
--     클라이언트 GPS 수집기(location_collector_service.dart)가 이미
--     distanceFilter: 10m로 스트림 이벤트 자체를 거른다. 그보다 살짝 큰
--     15m를 서버 디듀프 임계값으로 잡아, "클라가 이미 걸러서 보낸 진짜 이동"
--     까지 서버가 다시 죽이지 않게 여유를 둔다(GPS 노이즈가 보통 10~20m
--     수준이라는 것도 반영).
--   min_interval_seconds = 20:
--     클라이언트의 가장 빠른 전송 주기('moving' 상태 20초)와 맞춘다. 즉 이
--     디듀프는 실질적으로 'walking'(60초 간격, 15m 미만 이동이 잦음)과
--     'stationary'(300초 heartbeat, 이동 없음)에서 주로 발동하도록 설계했고,
--     'moving' 상태의 진짜 이동 스트림은 거의 건드리지 않는다.
--   두 조건을 AND로 묶은 이유: "많이 움직였지만 마지막 브로드캐스트가 방금
--   이었던 경우"(빠른 연속 이동)와 "안 움직였지만 오래 브로드캐스트가 없었던
--   경우"(장시간 정지 후 첫 heartbeat)를 둘 다 정상적으로 브로드캐스트해야
--   하기 때문이다 — OR로 묶으면 둘 중 하나가 과도하게 억제된다.
--
-- ── 나중에 실측으로 교정하는 방법 ──────────────────────────────────────────
--   1) 이 테이블 자체가 관측치를 쌓는다:
--        select sum(sent_count), sum(skip_count),
--               sum(skip_count)::numeric / nullif(sum(sent_count)+sum(skip_count), 0)
--          from public.location_broadcast_dedup_state;
--      skip 비율이 목표(예: Realtime 메시지 예산 대비)보다 낮으면 임계값을
--      올리고, 상대방이 체감하는 지연이 너무 크면 내린다.
--   2) Supabase 대시보드 Usage 탭의 Realtime Messages 그래프와 위 sent_count
--      합계를 대조하면 "메시지/핑" 실측 비율도 그대로 나온다(비용 분석
--      문서의 가정치를 실측치로 교체할 수 있음).
--   3) 교정은 코드/마이그레이션 변경 없이 아래 UPDATE 한 줄:
--        update public.realtime_broadcast_tuning
--           set min_distance_m = <새 값>, min_interval_seconds = <새 값>;
--      notify_location_ping()이 매 호출마다 이 표를 다시 읽으므로 즉시 반영된다.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) 튜닝 값 (싱글턴 행). service_role/postgres만 갱신, authenticated는 읽기도
--    불필요(브로드캐스트 판단은 서버 내부 로직이라 클라이언트에 노출할 이유
--    없음 — 임계값 자체가 알려지면 "어느 정도 움직여야 상대에게 보이는지"를
--    역이용할 수 있는 여지도 없진 않아 방어적으로 잠근다).
-- -----------------------------------------------------------------------------
create table public.realtime_broadcast_tuning (
  id boolean primary key default true check (id),  -- 싱글턴 행 패턴(행 1개만 허용)
  min_distance_m numeric not null default 15,
  min_interval_seconds int not null default 20,
  updated_at timestamptz not null default now()
);

comment on table public.realtime_broadcast_tuning is
  'notify_location_ping() 브로드캐스트 디듀프 임계값(싱글턴 1행). 실측 후 UPDATE로 교정, 재배포 불필요.';

insert into public.realtime_broadcast_tuning (id) values (true)
  on conflict (id) do nothing;

alter table public.realtime_broadcast_tuning enable row level security;
-- 정책을 의도적으로 하나도 만들지 않는다 — RLS는 켜져 있고 permissive 정책이
-- 없으므로 authenticated/anon 둘 다 모든 행이 안 보인다(postgres/service_role
-- 는 RLS 대상이 아니라 그대로 읽고 쓸 수 있음). grant 자체도 주지 않는다.
revoke all on public.realtime_broadcast_tuning from public, authenticated, anon;

create trigger trg_realtime_broadcast_tuning_set_updated_at
  before update on public.realtime_broadcast_tuning
  for each row
  execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 2) (user, group)별 "직전 브로드캐스트" 상태 + 관측용 카운터.
--    location_share_settings(사용자가 직접 설정하는 값)와 성격이 달라
--    별도 테이블로 분리한다(서버 내부 파생 상태, 클라이언트 권한 없음).
-- -----------------------------------------------------------------------------
create table public.location_broadcast_dedup_state (
  user_id uuid not null references public.profiles (id) on delete cascade,
  group_id uuid not null references public.relationship_groups (id) on delete cascade,
  last_location extensions.geography(Point, 4326),
  last_broadcast_at timestamptz,
  sent_count bigint not null default 0,
  skip_count bigint not null default 0,
  primary key (user_id, group_id)
);

comment on table public.location_broadcast_dedup_state is
  'notify_location_ping() 내부 전용. (user,group)별 마지막 브로드캐스트 위치/시각 + 실측 교정용 send/skip 카운터. 클라이언트 권한 없음.';

alter table public.location_broadcast_dedup_state enable row level security;
revoke all on public.location_broadcast_dedup_state from public, authenticated, anon;

-- -----------------------------------------------------------------------------
-- 3) notify_location_ping() 재정의: 그룹별 realtime.send() 직전에 디듀프 판단을
--    끼워 넣는다. p_location.user_id 재검증(HIGH-1) 등 기존 로직은 그대로다.
-- -----------------------------------------------------------------------------
create or replace function public.notify_location_ping(p_location public.user_locations)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_realtime boolean;
  v_group record;
  v_geog extensions.geography;
  v_payload jsonb;
  v_tuning record;
  v_last record;
  v_distance_m numeric;
  v_elapsed_s numeric;
begin
  -- 방어적 재검증: 이 함수는 upsert_location_ping() 내부에서만 호출되어야
  -- 하며, 그 경우 p_location.user_id는 항상 auth.uid()와 일치한다. grant
  -- 실수 등으로 클라이언트가 직접 호출하더라도 타인 명의로 브로드캐스트를
  -- 위조할 수 없도록 여기서도 반드시 재확인한다.
  if p_location.user_id is distinct from auth.uid() then
    raise exception 'cannot broadcast a location ping on behalf of another user';
  end if;

  select exists (select 1 from pg_namespace where nspname = 'realtime')
    into v_has_realtime;

  if not v_has_realtime then
    -- 실제 Supabase 플랫폼이 아닌 환경(예: 순수 로컬 Postgres 검증 환경)에서는
    -- 브로드캐스트를 생략한다. 클라이언트는 이 경우 postgres_changes 구독으로
    -- 대체 가능(README 참고).
    return;
  end if;

  select min_distance_m, min_interval_seconds
    into v_tuning
    from public.realtime_broadcast_tuning
   where id = true;

  for v_group in
    select rm.group_id, s.mode
    from public.relationship_members rm
    join public.location_share_settings s
      on s.relationship_group_id = rm.group_id
     and s.user_id = rm.user_id
    where rm.user_id = p_location.user_id
      and s.mode <> 'off'
      and (s.paused_until is null or s.paused_until <= now())
  loop
    select last_location, last_broadcast_at
      into v_last
      from public.location_broadcast_dedup_state
     where user_id = p_location.user_id
       and group_id = v_group.group_id;

    if v_last.last_location is not null and v_last.last_broadcast_at is not null then
      v_distance_m := extensions.st_distance(v_last.last_location, p_location.location);
      v_elapsed_s := extract(epoch from (now() - v_last.last_broadcast_at));

      -- 디듀프: 충분히 안 움직였고 AND 충분히 시간도 안 지났으면 이번
      -- 그룹의 브로드캐스트만 건너뛴다(저장은 이미 완료돼 영향 없음).
      if v_distance_m < v_tuning.min_distance_m
         and v_elapsed_s < v_tuning.min_interval_seconds
      then
        update public.location_broadcast_dedup_state
           set skip_count = skip_count + 1
         where user_id = p_location.user_id
           and group_id = v_group.group_id;
        continue;
      end if;
    end if;

    if v_group.mode = 'approx' then
      v_geog := extensions.st_setsrid(
        extensions.st_snaptogrid(p_location.location::extensions.geometry, 0.001, 0.001),
        4326
      )::extensions.geography;
    else
      v_geog := p_location.location;
    end if;

    v_payload := jsonb_build_object(
      'user_id', p_location.user_id,
      'longitude', extensions.st_x(v_geog::extensions.geometry),
      'latitude', extensions.st_y(v_geog::extensions.geometry),
      'accuracy_m', case when v_group.mode = 'approx' then null else p_location.accuracy_m end,
      'battery_level', p_location.battery_level,
      'is_charging', p_location.is_charging,
      'movement_state', p_location.movement_state,
      'captured_at', p_location.captured_at,
      'mode', v_group.mode
    );

    perform realtime.send(
      v_payload,
      'location_update',
      'relationship:' || v_group.group_id::text || ':location',
      true
    );

    insert into public.location_broadcast_dedup_state
      (user_id, group_id, last_location, last_broadcast_at, sent_count)
    values
      (p_location.user_id, v_group.group_id, p_location.location, now(), 1)
    on conflict (user_id, group_id) do update
      set last_location     = excluded.last_location,
          last_broadcast_at = excluded.last_broadcast_at,
          sent_count        = public.location_broadcast_dedup_state.sent_count + 1;
  end loop;
end;
$$;

comment on function public.notify_location_ping(public.user_locations) is
  'upsert_location_ping()에서만 호출되는 내부 헬퍼(클라이언트에 execute 권한 없음). relationship:{group_id}:location 토픽으로 위치 변경을 브로드캐스트. p_location.user_id = auth.uid() 검증으로 타인 명의 스푸핑을 차단. realtime_broadcast_tuning 임계값 기준으로 거리/시간이 둘 다 충분치 않으면 해당 그룹 브로드캐스트만 건너뛴다(저장에는 영향 없음).';

-- CREATE OR REPLACE는 기존 ACL을 보존하지만, HIGH-1 수정의 핵심(클라이언트
-- 직접 호출 차단)을 명시적으로 다시 선언해 둔다(방어적 재확인, 100002와
-- 동일한 관례).
revoke all on function public.notify_location_ping(public.user_locations) from public;
revoke execute on function public.notify_location_ping(public.user_locations) from authenticated;
