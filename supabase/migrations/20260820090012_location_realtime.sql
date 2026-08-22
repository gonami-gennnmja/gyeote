-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 변경 Realtime Broadcast
-- -----------------------------------------------------------------------------
-- upsert_location_ping() RPC가 저장을 마친 뒤 notify_location_ping()을 호출해
-- "relationship:{group_id}:location" 토픽으로 변경을 전파한다. Supabase의
-- Broadcast from Database 기능(realtime.send)을 사용한다.
--
--   realtime.send(payload jsonb, event text, topic text, private boolean)
--
-- 이 스키마/함수는 Supabase 플랫폼(Realtime 서버가 부트스트랩한 `realtime`
-- 스키마)에서만 존재한다. 순수 PostgreSQL(예: 이 저장소에서 RLS를 검증하기
-- 위해 쓰는 로컬 psql 환경)에는 `realtime` 스키마가 없으므로, 함수 내부에서
-- 스키마 존재 여부를 먼저 확인하고 없으면 조용히 아무 것도 하지 않는다
-- (마이그레이션 자체는 두 환경 모두에서 항상 적용 가능해야 하므로).
--
-- mode='approx'인 그룹에는 좌표를 get_peer_locations()와 동일하게 약 100m
-- 격자로 반올림해서 브로드캐스트한다 — 실시간 채널로도 정밀 좌표가 새어나가지
-- 않도록 서버가 강제한다.
--
-- ***Realtime Authorization 관련 중요 사항 (README에도 기재)***
-- 이 채널은 비멤버가 도청하지 못하도록 반드시 "Private" 채널로 구독해야 하며
-- (클라이언트: `supabase.channel(topic, { config: { private: true } })`),
-- 아래 DO 블록에서 `realtime.messages`에 RLS 정책을 걸어 그룹 멤버만 해당
-- 토픽을 구독(SELECT)할 수 있도록 제한한다. 이 RLS가 없으면 인증된 사용자
-- 누구나 임의의 관계 그룹 topic을 구독해 도청할 수 있으므로 반드시 필요하다.
-- =============================================================================

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
begin
  select exists (select 1 from pg_namespace where nspname = 'realtime')
    into v_has_realtime;

  if not v_has_realtime then
    -- 실제 Supabase 플랫폼이 아닌 환경(예: 순수 로컬 Postgres 검증 환경)에서는
    -- 브로드캐스트를 생략한다. 클라이언트는 이 경우 postgres_changes 구독으로
    -- 대체 가능(README 참고).
    return;
  end if;

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
  end loop;
end;
$$;

comment on function public.notify_location_ping(public.user_locations) is
  'upsert_location_ping()에서 호출. relationship:{group_id}:location 토픽으로 위치 변경을 브로드캐스트(realtime 스키마가 있는 환경에서만 동작).';

revoke all on function public.notify_location_ping(public.user_locations) from public;
grant execute on function public.notify_location_ping(public.user_locations) to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime Authorization: 그룹 멤버만 해당 위치 브로드캐스트 토픽을 구독 가능
-- realtime.messages 테이블은 Supabase 플랫폼에서만 존재하므로 DO 블록으로 감싸
-- 순수 로컬 Postgres 환경에서도 이 마이그레이션 전체가 에러 없이 적용되게 한다.
-- -----------------------------------------------------------------------------
do $outer$
begin
  if exists (select 1 from pg_namespace where nspname = 'realtime')
     and exists (
       select 1 from information_schema.tables
       where table_schema = 'realtime' and table_name = 'messages'
     )
  then
    execute 'alter table realtime.messages enable row level security';

    execute 'drop policy if exists "location_broadcast_group_members_only" on realtime.messages';

    execute $policy$
      create policy "location_broadcast_group_members_only"
      on realtime.messages
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.relationship_members m
          where m.user_id = auth.uid()
            and 'relationship:' || m.group_id::text || ':location' = realtime.topic()
        )
      )
    $policy$;
  else
    raise notice 'realtime.messages not found; skipping Realtime Authorization policy (local non-Supabase Postgres). Apply this migration against a real Supabase project so it takes effect.';
  end if;
end;
$outer$;
