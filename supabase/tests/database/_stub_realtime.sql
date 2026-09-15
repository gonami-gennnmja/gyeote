-- =============================================================================
-- 곁에(Gyeote) 로컬 전용 Realtime 최소 스텁 (커밋됨, 재사용 가능)
-- -----------------------------------------------------------------------------
-- 순수 로컬 Postgres(Docker/Supabase CLI 없는 샌드박스)에서 realtime.send()를
-- 호출하는 로직(notify_location_ping, 디듀프 등)을 검증하기 위한 최소
-- 스텁이다. `\ir _stub_realtime.sql` 로 필요한 테스트 파일 맨 앞에서 불러
-- 쓴다(예: realtime_broadcast_dedup.test.sql).
--
-- ⚠️ 실제 Supabase 프로젝트에서 실수로 이 파일을 돌려도 안전하다 —
-- realtime.messages가 이미 있으면(호스티드는 플랫폼이 기본 제공) 아래
-- 가드가 아무 것도 하지 않고 즉시 빠진다. realtime.send()의 진짜 구현을
-- 덮어쓰는 일은 없다. 이게 이 파일을 커밋해서 재사용하기로 한 이유이기도
-- 하다 — 인터페이스가 단순(4개 인자, 반환값 없음)하고 우리가 쓰는 방식이
-- 명확해 스텁이 실제 동작과 어긋날 여지가 작다(auth/extensions 스텁은
-- auth 서브시스템 전체의 축약된 대역이라 괴리 위험이 더 커서 계속
-- 비커밋으로 남겨둔다 — location_sharing_security.test.sql 헤더 참고).
--
-- 제공하는 것:
--   realtime.messages  — send() 호출을 기록하는 최소 테이블(브로드캐스트가
--                         "실제로 나갔는지"를 count(*)로 확인하는 용도).
--   realtime.send()     — 진짜 함수와 동일한 시그니처
--                         (jsonb, text, text, boolean) -> void. 호출될 때마다
--                         realtime.messages에 한 행 남긴다.
--   realtime.topic()    — 090012의 RLS 정책이 참조하지만 이 스텁 환경에서는
--                         정책 자체를 안 만들므로(realtime.messages가 이미
--                         있어야 그 정책이 걸리는데, 스텁이 방금 만든 새
--                         테이블에는 090012가 이미 지나가버려서 안 걸림)
--                         엄밀히는 안 쓰이지만, 참조가 있을 때 에러 없이
--                         빈 문자열을 주는 안전망으로 같이 넣어둔다.
-- =============================================================================

do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'realtime' and table_name = 'messages'
  ) then
    raise notice '_stub_realtime: realtime.messages가 이미 존재함 — 스텁을 건너뜀(실제 Supabase이거나 스텁이 이미 적용된 세션, 안전한 no-op).';
    return;
  end if;

  create schema if not exists realtime;

  execute 'create table realtime.messages (id bigint generated always as identity primary key, inserted_at timestamptz not null default now())';

  execute $fn$
    create function realtime.send(payload jsonb, event text, topic text, private boolean)
    returns void
    language plpgsql
    as $body$
    begin
      insert into realtime.messages default values;
    end;
    $body$
  $fn$;

  execute $fn$
    create function realtime.topic()
    returns text
    language sql
    as $body$ select ''::text $body$
  $fn$;

  raise notice '_stub_realtime: realtime.messages/send()/topic() 스텁 생성 완료.';
end
$$;
