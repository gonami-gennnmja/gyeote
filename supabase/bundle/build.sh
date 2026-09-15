#!/usr/bin/env bash
# =============================================================================
# 곁에(Gyeote) v0.1 초기 스키마 번들 빌더
# -----------------------------------------------------------------------------
# supabase/migrations/*.sql 를 파일명 순서로 하나의 SQL 파일로 결합한다.
# 결과: supabase/bundle/v0.1_initial.sql
#
# 용도: Supabase CLI 없이 대시보드 SQL Editor 에 한 번 붙여넣어 운영 DB에
#       초기 스키마를 적용하는 "경로 B" (supabase/DEPLOYMENT.md 참고).
#
# 마이그레이션을 추가/수정한 뒤에는 이 스크립트를 다시 돌려 번들을 갱신한다:
#   bash supabase/bundle/build.sh
#
# ⚠️ v0.1.0-rc1 태그 이후로는 이 번들을 더 돌리지 않는다. 운영에 v0.1 16개가
# 이미 적용돼 있으므로(경로 A, db push), v0.2+ 마이그레이션은 그냥
# `supabase db push`로 증분 적용하면 된다 — "초기 스키마를 CLI 없이 한 번에"
# 라는 이 번들의 용도 자체가 v0.1 부트스트랩 전용이었다. migrations/*.sql이
# 계속 늘어나도 이 스크립트를 무심코 다시 돌리면 v0.2+ 마이그레이션까지
# "v0.1_initial"에 섞여 들어가 이름과 내용이 어긋난다 — v0.1 부트스트랩이
# CLI 자체가 막혀 다시 필요해지는 경우가 아니면 재실행하지 말 것.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."          # supabase/
MIG_DIR="migrations"
OUT="bundle/v0.1_initial.sql"

mapfile -t FILES < <(ls "$MIG_DIR"/*.sql | sort)
N="${#FILES[@]}"

{
cat <<EOF
-- =============================================================================
-- 곁에(Gyeote) v0.1 초기 스키마 번들  (경로 B: 대시보드 SQL Editor 수동 적용)
-- -----------------------------------------------------------------------------
-- 이 파일은 supabase/bundle/build.sh 가 supabase/migrations/*.sql ${N}개를
-- 파일명 순서로 결합해 자동 생성한 것이다. 직접 편집하지 말 것 — 원본은
-- supabase/migrations/ 이고, 바뀌면 build.sh 를 다시 돌린다.
--
-- 적용 방법:
--   1) (선행) 대시보드 Database > Extensions 에서 pg_cron 을 활성화한다.
--      - pgcrypto / postgis 는 이 번들의 마이그레이션(20260820090001,
--        20260820090007)이 직접 create extension 한다. Supabase 호스티드는
--        두 확장이 available 기본 제공이라 보통 그대로 성공한다.
--      - pg_cron 은 20260903090001 이 create extension if not exists pg_cron 을
--        시도한다. 대시보드에서 먼저 켜두지 않으면 그 구문에서 하드 에러가
--        날 수 있고, 이 파일 전체가 하나의 트랜잭션(begin/commit)이므로
--        ${N}개 전부 롤백된다.
--   2) 대시보드 SQL Editor > New query > 이 파일 전체 붙여넣기 > Run.
--   3) 에러 없이 끝나면 완료. 아래 원장(schema_migrations) 기록까지 한
--      트랜잭션으로 반영된다.
--
-- 실패했을 때:
--   - 실패 지점 바로 위의  "-- >>> FILE k/${N}: <파일명>"  주석이 어느 원본
--     마이그레이션에서 멈췄는지 알려준다.
--   - 전체가 롤백됐으므로 DB는 원상태다. 원인을 그 원본 파일에서 고치고
--     build.sh 를 다시 돌린 뒤 재실행한다.
--   - pg_cron 때문에 20260903090001 에서만 막힌다면: 그 FILE 구간과 맨 끝
--     원장 insert 의 해당 줄만 빼고 실행 → 대시보드에서 pg_cron 활성화 →
--     그 구간 + 원장 줄을 따로 실행.
--
-- ⚠️ 맨 끝의 schema_migrations INSERT 블록을 지우지 말 것.
--   SQL Editor 로 수동 적용하면 원장이 비어 있어서, 나중에 CLI 로
--   'supabase db push' 하면 ${N}개를 처음부터 다시 적용하려 든다(사고).
--   이 블록이 ${N}개 버전을 원장에 기록해 두므로 수동 적용 후에도 CLI 운영이
--   정상이 된다.
--
-- 생성 시각 기준 대상 마이그레이션: ${N}개 (파일명 순).
-- =============================================================================

begin;

EOF

i=0
for f in "${FILES[@]}"; do
  i=$((i+1))
  base="$(basename "$f")"
  printf -- '-- >>> FILE %d/%d: %s >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n\n' "$i" "$N" "$base"
  cat "$f"
  printf -- '\n-- <<< END %s <<<\n\n\n' "$base"
done

cat <<'EOF'
-- =============================================================================
-- 마이그레이션 원장 기록
-- -----------------------------------------------------------------------------
-- 위 마이그레이션들이 이 DB에 적용됐음을 supabase_migrations.schema_migrations
-- 에 남긴다. 이후 'supabase db push' 는 원장에 없는 버전만 적용하므로, 이
-- 기록이 있어야 수동 적용분을 CLI 가 다시 적용하지 않는다.
--
-- 스키마/테이블이 없을 수도 있어 방어적으로 생성한다(신규 프로젝트엔 보통
-- 이미 존재한다). 컬럼 구성은 Supabase CLI 가 만드는 것과 동일하게 맞춘다.
-- =============================================================================
create schema if not exists supabase_migrations;

create table if not exists supabase_migrations.schema_migrations (
  version text not null primary key,
  statements text[],
  name text
);

EOF

printf -- 'insert into supabase_migrations.schema_migrations (version, name) values\n'
last=$((N))
i=0
for f in "${FILES[@]}"; do
  i=$((i+1))
  base="$(basename "$f" .sql)"
  version="${base%%_*}"
  name="${base#*_}"
  if [ "$i" -eq "$last" ]; then sep=";"; else sep=","; fi
  printf -- "  ('%s', '%s')%s\n" "$version" "$name" "$sep"
done | sed '$ s/;$/\non conflict (version) do nothing;/'

cat <<'EOF'

commit;

-- =============================================================================
-- 끝. 아래로 확인:
--   select version, name from supabase_migrations.schema_migrations order by version;
--   select count(*) from pg_policies where schemaname = 'public';
--   select proname from pg_proc where pronamespace = 'public'::regnamespace order by 1;
-- pg_cron 잡(20260903090001)은 supabase/DEPLOYMENT.md 의 "잡 등록 확인" 게이트로
-- 별도 확인:
--   select jobid, jobname, schedule, active from cron.job
--    where jobname = 'gyeote-location-history-retention';
-- =============================================================================
EOF
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT") lines, from $N migrations)"
