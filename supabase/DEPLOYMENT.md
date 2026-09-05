# 곁에(Gyeote) — 운영(호스티드) Supabase 배포 절차

이 문서는 로컬(`npx supabase start`)이 아니라 **운영 Supabase 프로젝트에
마이그레이션을 적용하고 v0.1 앱 빌드를 연결하는 절차**를 다룬다.
`supabase/README.md`는 로컬 개발만 다루므로, 운영 배포는 이 문서를 따른다.

> **현재 상태 (2026-09-03):** 이 리포만으로는 운영 Supabase 프로젝트의 존재
> 여부·설정을 알 수 없다. 아래 "가인님(프로젝트 오너) 확인 필요" 항목이
> 채워지기 전에는 v0.1을 배포할 수 없다. 추측으로 채우지 말 것.

---

## 0. 가인님(프로젝트 오너) 확인 필요 — 미확정 값

배포를 실행하기 전에 아래를 확정해 이 문서의 해당 칸을 채운다.

| 항목 | 채워야 하는 것 | 현재 값 |
|---|---|---|
| (a) 운영 프로젝트 | Supabase 프로젝트가 프로비저닝돼 있는지. 없으면 생성(region 포함) | _미확정_ |
| (a) project-ref | 프로젝트 API Settings의 Reference ID (`xxxxxxxxxxxxxxxxxxxx`) | _미확정_ |
| (a) region / plan | 배포 리전, 요금제(Free/Pro) | _미확정_ |
| (b) 적용된 마이그레이션 | 원격 DB에 지금까지 적용된 마이그레이션 번호(없으면 "없음") | _미확정_ |
| (c) SUPABASE_URL | `https://<project-ref>.supabase.co` | _미확정_ |
| (c) SUPABASE_ANON_KEY | 프로젝트 API Settings의 `anon` `public` 키 | _미확정_ |
| (d) 원격 PG 메이저 버전 | `show server_version;` 결과. `config.toml`은 `major_version = 17` 전제 | _미확정_ |
| (d) 확장 활성화 상태 | `postgis`, `pgcrypto`, `pg_cron` 활성 여부 (아래 3장) | _미확정_ |
| (e) service_role 키 보관처 | 스케줄러/관리 작업용. 절대 리포·앱 빌드에 넣지 않음 | _미확정_ |

---

## 1. 사전 준비 (로컬에서 1회)

```bash
# Supabase CLI 로그인 (브라우저 인증)
supabase login

# 이 리포를 운영 프로젝트에 연결. <project-ref>는 0장 (a).
supabase link --project-ref <project-ref>
```

`supabase link`는 `supabase/.temp/`에 연결 정보를 쓴다(이 디렉터리는 커밋하지
않는다). DB 비밀번호를 물으면 프로젝트 생성 시 설정한 Postgres 비밀번호를 넣는다.

---

## 2. 마이그레이션 적용

```bash
# 원격에 적용될 대기 마이그레이션 확인 (실제 적용 안 함)
supabase db push --dry-run

# 실제 적용
supabase db push
```

- `supabase/migrations/*.sql`을 **파일명 순서대로** 원격에 적용하고,
  `supabase_migrations.schema_migrations` 원장에 기록한다. 이후 push는 원장에
  없는 것만 증분 적용한다.
- **수동 `psql ... -f` 적용은 권장하지 않는다.** 원장이 남지 않아 다음 배포
  때 어디까지 적용됐는지 알 수 없게 된다. 부득이한 경우에만, 파일명 순서를
  반드시 지켜 전체를 한 번에 적용한다.
- 적용 대상 마이그레이션 목록과 설명은 `supabase/README.md`의 구조 섹션 참고
  (2026-09-03 기준 16개).

### 적용 후 검증 (아래 3개 모두 통과해야 "마이그레이션 적용 완료")

```bash
# 원격 스키마가 로컬 마이그레이션과 어긋나지 않는지
supabase db diff --linked   # 출력이 비어 있어야 정상

# 보안 회귀 테스트 (로컬에서 원격 DB URL 대상으로)
#   supabase/tests/database/location_sharing_security.test.sql
#   supabase/tests/database/location_sharing.test.sql
#   supabase/tests/database/invitation_email_check.test.sql
```

1. `supabase db push`가 에러 없이 끝났다.
2. `supabase db diff --linked` 출력이 비어 있다.
3. **pg_cron 정리 잡이 실제로 등록됐다.** 운영 DB에서 아래를 조회했을 때
   **정확히 1행이 나오고 그 행의 `active` 가 `true`** 여야 한다:
   ```sql
   select jobid, jobname, schedule, command, active
     from cron.job
    where jobname = 'gyeote-location-history-retention';
   ```
   `db push` 성공만으로는 이게 보장되지 않는다(pg_cron 미활성이면 가드가 조용히
   통과하므로). 행이 0개거나 `active = false`면 마이그레이션 적용은 미완료로
   간주한다. 원격에 SQL을 실행하는 구체적 방법과 조치는
   [3장 "잡 등록 확인"](#cron-job-verify) 참고.

---

## 3. 확장(Extension) 활성화

마이그레이션의 `create extension if not exists ...`는 해당 확장이 **available**
해야 성공한다. Supabase 호스티드는 대부분 available이지만 일부는 대시보드에서
먼저 켜야 한다.

| 확장 | 필요 이유 | 활성화 방법 |
|---|---|---|
| `pgcrypto` | 초대 코드 생성(`gen_random_bytes`) | `20260820090001`이 자동 활성화. 보통 추가 조치 불필요 |
| `postgis` | 위치 좌표/격자 반올림(`ST_SnapToGrid` 등) | `20260820090007`이 자동 활성화. Supabase는 available 기본 제공 |
| `pg_cron` | `location_history` 보존기간 정리 스케줄 | 대시보드 Database > Extensions에서 활성화(권장 — 아래 참고). 활성화 이전 상태에서 이 마이그레이션이 어떻게 반응하는지는 **미확인** |

### pg_cron

- `20260903090001_schedule_location_history_retention.sql`이
  `gyeote-location-history-retention` 잡(매일 17:17 UTC = 02:17 KST)을 등록한다.

**가드-true 경로 로컬 재현 검증됨 (2026-09-05, Tom).** 상세:
`pg_cron_guard_true_verification_2026-09-05.md`(Tom scratchpad).

- **검증된 것.** 로컬 PG14에 `postgresql-14-cron` 패키지를 설치하고
  `shared_preload_libraries = 'pg_cron'`을 **먼저 설정한 뒤 Postgres를
  재시작한** 상태에서 이 마이그레이션을 실행했다. 이 상태(=pg_cron이 이미
  preload된 상태)에서는 `create extension if not exists pg_cron` → `cron.job`
  실제 행 생성 → `postgres` 역할 실행 성공, 그리고 grant 없는 역할에서
  `permission denied` 재현까지 SQL 레벨 동작이 4개 항목 전부 실제 실행으로
  확인됐다. 패키지 자체가 없는 상태(설치 전)에서는 `pg_available_extensions`에
  pg_cron이 없어 가드가 NOTICE-and-skip으로 빠지는 것도 확인됐다.
- **검증되지 않은 것 — 과대해석 금지.** 이 재현은 "**대시보드 토글을 이미
  켠 뒤**의 동작"을 재현한 것이지, "**대시보드 토글을 아직 안 켠 상태**에서
  `db push`를 돌리면 어떻게 되는가"는 재현하지 않았다(`shared_preload_libraries`
  설정+재시작을 Tom이 먼저 손으로 했기 때문 — Rena 지적, 2026-09-05). 즉
  운영에서 pg_cron을 한 번도 활성화한 적 없는 프로젝트에 이 마이그레이션을
  먼저 돌리면 실제로 무슨 일이 일어나는지는 **여전히 미확인**이다. 가능한
  시나리오 최소 두 가지를 열어둔다:
  - (가) `pg_available_extensions`에 pg_cron이 없어 가드가 조용히 NOTICE만
    남기고 통과 (지금까지 문서가 가정해온 실패 모드).
  - (나) `pg_available_extensions`에는 있지만 `shared_preload_libraries`에는
    없어서 `create extension pg_cron` 자체가 하드 에러로 실패 — 이 경우
    DO 블록이 예외를 던지므로 `supabase db push`가 "성공"으로 끝나지 않고
    그 자리에서 실패로 드러난다(=오히려 (가)보다 눈에 잘 띄는 실패).
  - 어느 쪽이 맞는지, 혹은 Supabase가 모든 프로젝트에 pg_cron을 이미
    preload해둬서 애초에 이 분기 자체가 발생하지 않는지는 실제 운영
    프로젝트에서 처음 배포할 때 확인된다.
- **어느 시나리오든 게이트가 잡아낸다.** (가)처럼 조용히 스킵되면
  [잡 등록 확인](#cron-job-verify) 쿼리에서 `cron.job` 행이 0개로 나와 걸린다.
  (나)처럼 `create extension`이 하드 에러면 `db push` 자체가 실패로
  보고되어 배포 담당이 그 자리에서 알아챈다. 두 경우 모두 "배포가 성공한
  것처럼 보이는데 정리 잡만 조용히 없는" 상태로는 끝나지 않는다 — 대시보드
  Database > Extensions에서 pg_cron을 **먼저 활성화하고** `supabase db push`
  를 돌리는 순서를 권장 경로로 유지한다.
  1. 대시보드 Database > Extensions에서 `pg_cron` 활성화
  2. `supabase db push` 실행/재실행 (재실행 자체는 안전 — 잡 이름 기준 upsert,
     Tom이 재실행 멱등성도 확인함)
  3. [잡 등록 확인](#cron-job-verify) 게이트 통과 확인
  4. pg_cron을 끝내 쓸 수 없으면 아래 2안(예약 Edge Function)으로 전환

> ⚠️ **`db push` "성공"이 잡 등록을 보장하지 않는다 — 반드시 별도 확인.**
> 검증된 건 "이미 활성화된 상태에서의 SQL 레벨 동작"뿐이고, "활성화 이전
> 상태에서 처음 배포할 때 무슨 일이 나는가"는 미확인이다. 검증 안 된 걸
> 검증된 것처럼 적으면 이번 라운드 내내 잡아온 "성공처럼 보이는 실패"를
> 문서 자체가 재현하는 꼴이 된다. 그러니 어느 시나리오가 실제인지와 무관하게,
> **`db push` 성공 여부와 무관하게, 아래 "잡 등록 확인"을 독립 항목으로
> 반드시 통과시킨다.** 이게 확인되면 `location_history`가 무한정 쌓여
> 개인정보처리방침의 "위치 이력 14일 보관"이 허위가 되는 상황을 막는다.

<a id="cron-job-verify"></a>
#### 잡 등록 확인 (배포 완료 필수 게이트)

**운영 DB에 SQL을 실행하는 방법 (둘 중 하나):**

- **A. Supabase 대시보드 SQL Editor** — 프로젝트 대시보드 좌측 메뉴 `SQL Editor`
  → `New query` → 아래 쿼리 붙여넣고 `Run`. 별도 접속 정보 불필요, 가장 간단.
- **B. `psql` 직접 접속** — 프로젝트 대시보드 `Project Settings > Database` →
  `Connection string` 의 **Session pooler** 또는 **Direct connection** 문자열을
  복사해서:
  ```bash
  psql "postgresql://postgres.<project-ref>:<DB-PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres"
  ```
  (`<DB-PASSWORD>`는 프로젝트 생성 시 설정한 Postgres 비밀번호. 대시보드에서
  재설정 가능.) `supabase db push` 에 쓰는 것과 같은 자격증명이다.

> `supabase db diff --linked` 는 SQL을 임의로 실행해주지 않는다 — 위 A 또는 B로
> 직접 조회해야 한다.

**조회 쿼리:**

```sql
-- 1) 잡이 실제로 존재하고 active인지 — 행이 0개면 배포 미완료
select jobid, jobname, schedule, command, active
  from cron.job
 where jobname = 'gyeote-location-history-retention';

-- 2) (배포 다음날 이후) 실행 이력
select status, return_message, start_time, end_time
  from cron.job_run_details
 where jobid = (select jobid from cron.job
                where jobname = 'gyeote-location-history-retention')
 order by start_time desc
 limit 10;
```

- **쿼리 1의 결과가 1행이고 `active = true`가 아니면 배포를 완료로 치지
  않는다.** 마이그레이션이 "성공"했더라도 마찬가지다 — pg_cron 미활성이면
  마이그레이션은 성공하고 잡은 없다.
- 쿼리 1이 `ERROR: relation "cron.job" does not exist` 를 내면 pg_cron 확장
  자체가 안 켜진 것이다 → 대시보드에서 활성화.
- 잡이 없으면: 대시보드에서 `pg_cron` 활성화 → `supabase db push` 재실행 →
  이 쿼리를 다시 통과시킨다. 또는 아래 2안으로 전환한다.

- **pg_cron을 쓸 수 없는 경우(2안, 폴백):** Supabase 예약 Edge Function을 만들어
  cron 트리거로 `service_role` 키를 써서
  `select public.delete_expired_location_history();` 를 호출한다. 이때 잡 등록
  마이그레이션은 그대로 두어도 무방하다(NOTICE만 남고 아무것도 안 함).
  이 경우 위 "잡 등록 확인" 게이트는 "예약 Edge Function이 등록됐고 최근 실행
  기록이 있는지" 확인으로 대체한다 — 정리 경로가 **하나는 반드시 살아 있어야**
  배포 완료다.

---

## 4. 앱 빌드에 연결

`app/lib/core/config/env_config.dart`는 `--dart-define` 또는 `app/.env`에서
`SUPABASE_URL` / `SUPABASE_ANON_KEY`를 읽는다. **`anon` 키만 앱에 넣는다.
`service_role` 키는 절대 앱/리포에 넣지 않는다.**

```bash
# 예: 릴리즈 빌드
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

`app/.env.example`을 복사해 `app/.env`를 만들어 채우는 방식도 가능(`.env`는
gitignore 대상 — 현재 `.gitignore`에 `.env` 패턴 추가 필요 여부 확인).

---

## 5. Auth 설정 (대시보드에서 확인/조정)

`config.toml`의 `[auth]` 값은 **로컬 스택 전용**이며 운영에는 적용되지 않는다.
운영 Auth 설정은 대시보드 Authentication에서 직접 맞춘다.

| 항목 | 로컬 `config.toml` 값 | 운영에서 확인할 것 |
|---|---|---|
| 이메일 확인(`enable_confirmations`) | `false` | v0.1 정책 결정에 따름. **켜면** 앱의 `email_not_confirmed` 안내 카피가 실제로 동작. 끄면 그 분기는 도달 불가(카피는 방어적으로 유지) |
| 회원가입 허용(`enable_signup`) | `true` | v0.1 공개 범위에 맞게 |
| 최소 비밀번호 길이 | `6` | 필요 시 상향 |
| 계정 열거 보호 | (config.toml에 항목 없음) | 대시보드에 해당 토글이 있으면 상태 확인. `config.toml`로는 관리 불가 |
| SMTP | 로컬 캡처 서버 | 운영 SMTP(SendGrid 등) 설정 필요 — 비밀번호 재설정/이메일 확인 메일 발송에 필수 |

---

## 6. 배포 후 스모크 체크

- 신규 가입 → 프로필 자동 생성(`handle_new_user` 트리거) 동작
- 관계 그룹 생성 → 초대 코드 발급 → 다른 계정으로 수락
- 위치 핑 업서트 → 상대 앱에 실시간 반영(Realtime Broadcast, private 채널)
- `get_peer_locations`가 비멤버에게 빈 결과인지
- **`location_history` 정리 잡이 등록돼 있는지 — `cron.job`에
  `gyeote-location-history-retention` 행이 존재하고 `active = true`인지 직접
  조회([3장 "잡 등록 확인"](#cron-job-verify)). 없으면 배포 완료 아님.**
  (2안으로 갔다면: 예약 Edge Function이 등록돼 있고 실행되는지 확인.)
- 하루 뒤 `cron.job_run_details`에 retention 잡 실행 기록이 남는지 (`status`가
  `succeeded`인지, `return_message`에 삭제 행 수가 찍히는지)

---

## 7. 배포 완료 기준 (전부 충족해야 v0.1 백엔드 배포 완료)

- [ ] 0장 미확정 값(a~e)이 전부 채워졌다.
- [ ] `supabase db push` 성공 + `supabase db diff --linked` 출력 비어 있음.
- [ ] 보안 회귀 테스트 3종이 원격 DB 대상으로 PASS.
- [ ] **정리 경로가 살아 있다 (둘 중 하나):**
  - 1안: `cron.job`에 `gyeote-location-history-retention` 행이 있고
    `active = true` ([3장 잡 등록 확인](#cron-job-verify)). — **`db push`
    "성공"과 별개로 이 쿼리를 직접 돌려 확인. 행이 없으면 배포 미완료.**
  - 2안: 예약 Edge Function이 등록됐고 최근 실행 기록이 있다.
- [ ] 앱 릴리즈 빌드에 운영 `SUPABASE_URL` / `anon` 키가 주입됐다(`service_role`
  키는 앱에 없음).
- [ ] 운영 SMTP 설정 완료(비밀번호 재설정 메일 발송 경로).
- [ ] 6장 스모크 체크 통과.
