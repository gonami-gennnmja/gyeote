# 곁에(Gyeote) — 운영(호스티드) Supabase 배포 절차

이 문서는 로컬(`npx supabase start`)이 아니라 **운영 Supabase 프로젝트에
마이그레이션을 적용하고 v0.1 앱 빌드를 연결하는 절차**를 다룬다.
`supabase/README.md`는 로컬 개발만 다루므로, 운영 배포는 이 문서를 따른다.

> **현재 상태 (2026-09-14):** 마이그레이션 16개 **전부 운영에 적용 완료**
> (경로 A, `db push`). 도중 `20260820090012`에서 `must be owner of table
> messages` 에러로 한 번 막혔고 — 로컬 통과 ≠ 운영 통과가 실제로 터진
> 사례(아래 §2 "실제로 이게 터진 사례" 참고) — `dc02bf9`로 고치고 재적용해
> 통과했다. 적용 결과: public 테이블 7개, RLS 정책 12개, 함수 20개, 원장
> 16행, pg_cron 잡 등록·`active=true`, `realtime.messages` 정책 생성 확인.
> 남은 건 §0의 (d)/(e) 미확인 값과 §6 스모크 체크.

---

## 0. 운영 프로젝트 값

| 항목 | 값 | 상태 |
|---|---|---|
| (a) 운영 프로젝트 | 프로비저닝됨 | **확정** (2026-09-06) |
| (a) project-ref | `cpaxqjqijrawmevzivwz` | **확정** |
| (a) region | `ap-northeast-2` (서울) | **확정** |
| (a) plan | — | 미확인(배포에 필수 아님) |
| (b) 적용된 마이그레이션 | **16개 전부** (public 테이블 7, RLS 정책 12, 함수 20) | **확정** (2026-09-14, `dc02bf9` 이후 `db push` 완료) |
| (c) SUPABASE_URL | `https://cpaxqjqijrawmevzivwz.supabase.co` | **확정** |
| (c) SUPABASE_ANON_KEY | 확보됨 — `app/.env`에 있음(gitignore 대상, 리포에 커밋 안 함) | **확정** |
| (d) 원격 PG 메이저 버전 | — | 미확인(배포 자체는 통과했으므로 급하지 않음). 확인하려면 `show server_version;` |
| (d) 확장 활성화 상태 | `postgis` / `pgcrypto` / `pg_cron` | **확정 — 셋 다 동작 확인.** `pg_cron` 잡 `gyeote-location-history-retention` 등록·`active=true`까지 확인(2026-09-14) |
| (e) service_role 키 보관처 | — | 미정. 스케줄러/관리 작업용, 절대 리포·앱 빌드에 넣지 않음 |
| **db push 실행 수단** | Supabase 액세스 토큰(`SUPABASE_ACCESS_TOKEN`) **또는** DB 비밀번호 | **확보·사용됨** — 가인님이 직접 실행(2026-09-14). 이후 재적용/증분 적용에도 동일 수단 필요 |
| (f) Auth 이메일 확인 | **운영은 이메일 확인 필수** (`auth/v1/settings`의 `mailer_autoconfirm = false`) | **확정** (2026-09-06). 로컬 `config.toml`의 `enable_confirmations = false`와 정반대 — 5장 참고 |

---

## 배포 경로 선택 — A(CLI) vs B(SQL Editor)

마이그레이션을 운영에 적용하는 방법은 두 가지다. **결과는 동일**하고(같은 16개
마이그레이션 + 원장 기록), 이후 CLI 운영도 둘 다 정상이다.

| | 경로 A — `supabase db push` | 경로 B — 대시보드 SQL Editor 번들 |
|---|---|---|
| 필요한 것 | Supabase CLI 설치 + 액세스 토큰(또는 DB 비밀번호) | 대시보드 로그인만 |
| 방법 | 1~2장 | 2-B장 (`supabase/bundle/v0.1_initial.sql` 붙여넣기) |
| 증분 적용 | 됨 (이후 마이그레이션은 원장 비교로 자동) | 첫 적용만. 이후 마이그레이션은 경로 A 또는 새 번들 |
| 실패 시 | 마이그레이션 단위로 멈춤, 그 파일만 고치고 재푸시 | 전체가 한 트랜잭션 → 전부 롤백, 고치고 재실행 |
| 원장 | CLI가 자동 기록 | 번들 맨 끝 INSERT 블록이 기록 (지우지 말 것) |

**언제 무엇을:**
- **CLI가 이미 있고 토큰을 만들 수 있으면 → 경로 A.** 앞으로 v0.2~v0.4
  마이그레이션도 계속 나오므로, 한 번 세팅해두면 이후가 편하다.
- **지금 당장 CLI 설치·토큰 발급이 부담이거나, 심사 마감이 급하면 → 경로 B.**
  대시보드에서 붙여넣기 한 번이면 끝난다. 단 다음 마이그레이션 때는 경로 A로
  넘어가거나(원장이 이미 채워져 있어 자연스럽게 이어진다) 갱신된 번들을 다시
  붙여넣어야 한다.
- 경로 B로 적용한 뒤 나중에 경로 A로 전환해도 안전하다 — 번들이 원장에 16개를
  기록해두므로 `db push`가 그걸 "이미 적용됨"으로 인식하고 건너뛴다.

---

## 1. (경로 A) 사전 준비 — 로컬에서 1회

```bash
# 1) Supabase CLI 로그인 — 둘 중 하나
supabase login                       # 브라우저 인증 (대화형)
# 또는 비대화형:
export SUPABASE_ACCESS_TOKEN=<액세스 토큰>   # 대시보드 Account > Access Tokens에서 발급

# 2) 이 리포를 운영 프로젝트에 연결
supabase link --project-ref cpaxqjqijrawmevzivwz
# DB 비밀번호를 물으면 프로젝트 생성 시 설정한 Postgres 비밀번호 입력
# (대시보드 Project Settings > Database > Database password에서 재설정 가능)
```

`supabase link`는 `supabase/.temp/`에 연결 정보를 쓴다(이 디렉터리는 커밋하지
않는다).

> **실행 주체:** 이 세션(및 CI)에는 액세스 토큰도 DB 비밀번호도 없다. 아래
> 명령은 **가인님이 직접 실행**하거나, `SUPABASE_ACCESS_TOKEN`을 안전하게
> 제공해야 백엔드 담당이 실행할 수 있다.

---

## 2. (경로 A) 마이그레이션 적용 — CLI (최초 배포, 현재 원격은 빈 스키마)

```bash
# 원격에 적용될 대기 마이그레이션 확인 (실제 적용 안 함, 원격에 연결만)
supabase db push --dry-run
# → migrations/*.sql 16개 전부 "pending"으로 떠야 정상 (원격이 비어 있으므로)

# 실제 적용
supabase db push
```

원격 PG 메이저 버전이 `config.toml`의 `major_version = 17`과 맞는지는 확인해
두면 좋다(불일치하면 `db diff`가 오작동할 수 있음). 대시보드 SQL Editor에서
`show server_version;`, 또는 [3장의 psql 접속 문자열](#cron-job-verify)로:

```bash
psql "<대시보드 Project Settings > Database의 connection string>" -tAc "show server_version;"
```

- `supabase/migrations/*.sql`을 **파일명 순서대로** 원격에 적용하고,
  `supabase_migrations.schema_migrations` 원장에 기록한다. 이후 push는 원장에
  없는 것만 증분 적용한다.
- **수동 `psql ... -f` 적용은 권장하지 않는다.** 원장이 남지 않아 다음 배포
  때 어디까지 적용됐는지 알 수 없게 된다. 부득이한 경우에만, 파일명 순서를
  반드시 지켜 전체를 한 번에 적용한다.
- 적용 대상 마이그레이션 목록과 설명은 `supabase/README.md`의 구조 섹션 참고
  (2026-09-03 기준 16개).

### ⚠️ 로컬 통과 ≠ 운영 통과 — `db push`는 처음 도는 경로다

QA가 로컬 `gyeote_test`(순수 PG14)에서 마이그레이션을 검증할 때는 `auth`
스키마, `authenticated`/`service_role`/`anon` 역할, `auth.uid()` 등을 **스텁으로
직접 만들어** 돌렸다(순수 Postgres에는 이것들이 없기 때문). 따라서 **로컬
통과가 뜻하는 건 "SQL 문법과 로직이 성립한다"까지이고**, 실제 Supabase
환경에서 `auth.users` 참조·역할 grant·`realtime`/`cron` 스키마 상호작용이
그대로 먹는다는 보장은 아니다. `supabase db push`는 이 리포에서 **처음으로
실제 Supabase에 적용되는 경로**이며, `--dry-run`은 실행이 아니라 적용 계획만
보여준다(스텁 없는 진짜 환경에서의 성공 여부는 알려주지 않는다).

#### 실제로 이게 터진 사례 (2026-09-14, 운영 최초 적용)

이론이 아니라 실제로 이 문서가 우려한 그 형태로 막혔다. 무슨 에러가 어디서
왜 났는지 그대로 남긴다 — 다음에 비슷한 걸 또 만들 때 같은 데서 헤매지 않기
위해서다.

- **증상:** 운영 프로젝트에 첫 `db push`(경로 A)를 실행하자
  `20260820090012_location_realtime.sql`에서
  `ERROR: must be owner of table messages`로 멈췄다. 이 파일 전체가 하나의
  마이그레이션(트랜잭션)이라 이 파일만 롤백되고, **번들(경로 B)로 시도했다면
  16개 전부 롤백됐을 것**이다.
- **원인:** 이 마이그레이션의 DO 블록은 `realtime.messages` 테이블 존재
  여부만 `information_schema.tables`로 확인한 뒤, 무조건
  `alter table realtime.messages enable row level security`를 실행했다.
  로컬 `gyeote_test`에서는 이 테이블을 우리가(=`postgres`로) 직접 만들어서
  소유자가 맞았기 때문에 통과했다. **호스티드 Supabase에서는
  `realtime.messages`의 소유자가 `supabase_realtime_admin`이고 RLS도 이미
  켜져 있다** — `postgres`는 그 테이블의 소유자가 아니므로
  `ALTER TABLE ... ENABLE/DISABLE ROW LEVEL SECURITY`가 권한 에러로
  거부된다(Postgres에서 이 ALTER는 오너십을 요구한다). 즉 "로컬에서 우리가
  만든 테이블"과 "운영에서 플랫폼이 이미 만들어둔 같은 이름의 테이블"이
  소유자가 다르다는, 스텁으로는 절대 드러나지 않는 종류의 차이였다.
- **수정:** `pg_class.relrowsecurity`로 RLS가 이미 켜져 있는지 먼저 보고,
  켜져 있으면 그 ALTER를 건너뛴다(꺼져 있을 때만 시도). **`CREATE POLICY`는
  오너십이 없어도 허용된다는 것을 운영에서 직접 확인**했다(Supabase가
  Realtime Authorization을 위해 문서화해 둔 공식 지원 경로라 `postgres`에
  정책 관리 권한만 별도로 부여돼 있는 것으로 보인다 — ALTER는 막고 정책은
  허용하는 이 비대칭은 "고객이 RLS를 끄는 건 막되 정책은 커스터마이즈하게
  둔다"는 Supabase 쪽 설계로 추정, 공식 확인은 아님).
- **커밋:** `dc02bf9`. 적용 결과: public 테이블 7개, RLS 정책 12개, 함수
  20개, 원장 16행, pg_cron 잡 등록·`active=true`, `realtime.messages` 정책
  생성까지 전부 확인.
- **왜 로컬에서 못 잡았나 — 근본 원인.** 이 클래스의 버그는 "그 객체를
  누가 만들었는지"가 로컬 스텁과 운영에서 다를 때만 생긴다. 우리가 만드는
  `public.*` 테이블은 로컬·운영 어디서 적용하든 우리가 소유자이므로 안전하다.
  위험한 건 **플랫폼이 미리 만들어 둔 객체**(`auth.users`, `realtime.messages`,
  향후 `storage.*` 등)를 건드리는 구문 — 그중에서도 오너십을 요구하는 DDL
  (`ALTER TABLE ... ENABLE/DISABLE RLS`, `ALTER ... OWNER TO`, 시퀀스/타입
  오너십 변경 등)이다. 반대로 **권한(GRANT)만 있으면 되는 조작**
  (`CREATE TRIGGER`, `CREATE POLICY`, 함수 `EXECUTE` 호출)은 오너십이 없어도
  Supabase가 플랫폼 표준 워크플로로 지원하는 한 대개 통과한다(`auth.users`
  트리거, 이번 `realtime.messages` 정책 둘 다 이 경우).
- **일반화한 점검 기준 (다음에 플랫폼 소유 객체를 건드릴 때):** 그 구문이
  "오너십이 있어야만 허용"되는 부류(ALTER TABLE의 RLS on/off, OWNER TO)인지,
  아니면 "GRANT만 있으면 되는" 부류(CREATE POLICY/TRIGGER, 함수 호출)인지
  먼저 구분한다. 전자면 로컬 스텁이 통과시켜도 운영에서 막힐 수 있다고 가정
  하고, 무조건 실행하지 말고 **현재 상태를 먼저 조회해 조건부로 실행**한다
  (이번 수정이 `pg_class.relrowsecurity`로 한 것과 같은 패턴).

### 첫 `db push`가 중간에 깨졌을 때

`db push`는 마이그레이션을 파일명 순서로 하나씩 적용하고, **각 파일이 성공하면
`supabase_migrations.schema_migrations`에 그 버전을 기록**한다. 중간에서 실패하면
그 앞 파일들은 이미 원격에 적용된 채로 남는다(부분 적용 상태).

1. **에러 메시지에서 어느 파일에서 멈췄는지 확인** — `db push` 출력이 실패한
   마이그레이션 파일명과 Postgres 에러(제약조건명/스키마 객체명 등)를 찍는다.
2. **원격에 어디까지 적용됐는지 확인:**
   ```sql
   select version, name
     from supabase_migrations.schema_migrations
    order by version;
   ```
   여기 찍힌 마지막 `version`까지가 적용된 것이다. 다음 번호부터가 미적용.
3. **실패한 그 파일만 고친다** — 스키마를 손으로 되돌리지 말 것. 원인(대개
   스텁으로 가려졌던 `auth`/역할/스키마 의존성)을 그 마이그레이션 파일에서
   수정한다. 이미 원장에 기록된 앞 파일은 건드리지 않는다.
4. **재푸시:** `supabase db push` — 원장에 없는(=실패 지점 이후) 파일만 다시
   적용을 시도한다. 앞 파일을 재실행하지 않으므로 안전하다.
5. 반복해서 통과할 때까지. 통과 후 아래 "적용 후 검증"으로 넘어간다.

> 원격이 부분 적용 상태로 남아도 데이터는 없으므로(신규 프로젝트) 최악의 경우
> 대시보드에서 프로젝트 DB를 리셋하고 처음부터 다시 push해도 된다 — 단
> Auth에 이미 만든 계정이 있으면 사라지니 확인.

---

## 2-B. (경로 B) 마이그레이션 적용 — 대시보드 SQL Editor 번들

CLI 없이, 대시보드 붙여넣기 한 번으로 초기 스키마를 적용한다.

**파일:** `supabase/bundle/v0.1_initial.sql`
(`supabase/bundle/build.sh` 가 `migrations/*.sql` 16개를 파일명 순서로 결합해
생성. 마이그레이션이 바뀌면 `bash supabase/bundle/build.sh` 로 다시 만든다.)

### 순서

1. **먼저 `pg_cron` 을 활성화한다** — 대시보드 Database > Extensions > `pg_cron`
   토글 ON. (번들의 마지막 마이그레이션이 `create extension pg_cron` 을 하는데,
   pg_cron 이 preload 안 돼 있으면 그 구문이 하드 에러 → 번들 전체가 한
   트랜잭션이라 16개 전부 롤백된다. `pgcrypto`/`postgis` 는 번들이 알아서
   처리하므로 조작 불필요.)
2. 대시보드 **SQL Editor > New query** > `v0.1_initial.sql` **전체** 붙여넣기 >
   **Run**.
3. 에러 없이 끝나면 완료. 번들 맨 끝의 `begin; … commit;` 안에서 스키마 16개 +
   `supabase_migrations.schema_migrations` 원장 기록까지 원자적으로 반영된다.
4. 아래 "경로 공통 — 적용 후 검증" 으로 넘어간다.

### 실패했을 때

- 번들은 `begin; … commit;` 로 감싸여 있어 **어느 한 구문이라도 실패하면 전부
  롤백**된다(DB는 원상태). 부분 적용 상태가 남지 않는다.
- 실패 지점 바로 위의 `-- >>> FILE k/16: <파일명>` 주석이 **어느 원본
  마이그레이션에서 멈췄는지** 알려준다.
- 원인을 그 원본 파일(`supabase/migrations/…`)에서 고치고 → `build.sh` 재실행
  → 번들 재실행.
- **`20260903090001` (FILE 16/16) 에서만 막힌다면** (대개 pg_cron): 그 FILE 16
  구간과 맨 끝 원장 INSERT 의 `('20260903090001', …)` 줄만 빼고 Run → 대시보드
  에서 pg_cron 활성화 → 뺐던 두 조각만 따로 Run.

> ⚠️ **번들 맨 끝 `schema_migrations` INSERT 블록을 지우고 실행하지 말 것.**
> SQL Editor 수동 적용은 원장을 안 남기므로, 이 블록이 없으면 나중에
> `supabase db push` 가 16개를 **처음부터 다시** 적용하려 든다(다음 마이그레이션
> 때 사고). 이 블록이 16개 버전을 원장에 기록해 두면 경로 B 이후에도 CLI 운영이
> 정상이다.

### 경로 B 이후 다음 마이그레이션(v0.2~)

원장이 채워져 있으므로 그때는 **경로 A(`supabase db push`)로 자연스럽게 이어
가면 된다** — 원장에 없는 새 버전만 적용된다. 계속 CLI 없이 가려면
`build.sh` 로 새 번들을 만들어 같은 방식으로 붙여넣는다(단 그 번들의 원장
INSERT 는 새로 추가된 마이그레이션 버전만 넣도록 조정 필요).

---

## 적용 후 검증 (경로 A·B 공통 — 아래 3개 모두 통과해야 "적용 완료")

- (경로 A) `supabase db diff --linked` 출력이 비어 있다.
- (경로 B) 아래 스모크 쿼리로 스키마가 실제로 생겼는지 확인:
  ```sql
  select count(*) from information_schema.tables where table_schema = 'public';  -- 7
  select count(*) from pg_policies where schemaname = 'public';                   -- 12 이상
  select version from supabase_migrations.schema_migrations order by version;     -- 16행
  ```
- **보안 회귀 테스트 3종**을 원격 DB 대상으로 실행:
  `supabase/tests/database/location_sharing_security.test.sql`,
  `location_sharing.test.sql`, `invitation_email_check.test.sql`
- **pg_cron 정리 잡 등록 확인** — [3장 "잡 등록 확인"](#cron-job-verify) 게이트.
  `db push`/번들 "성공" 과 별개로 `cron.job` 에 행이 실제로 있는지 직접 조회한다
  (`docs/legal/privacy.html` 의 14일 보관 약속이 이 확인에 걸려 있다).

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

> **이 확인은 운영 편의가 아니라 게시된 방침 문구의 진위 확인이다.**
> `docs/legal/privacy.html`이 사용자에게 "위치 이동 이력: 수집일로부터 최대
> 14일간 보관 후 자동 삭제"(개인정보 파기 절차로 "자동화된 정기 삭제
> 절차"라고 명시)를 약속한다. 이 약속이 실제로 지켜지는지는 오직 retention
> 잡이 등록돼 실제로 도는지에 달려 있다 — 잡이 없으면 그 문구는 배포 첫날부터
> 거짓이 된다. 아래 쿼리를 건너뛰거나 가볍게 보면 안 되는 이유가 여기 있다.

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
  않는다.** 마이그레이션이 "성공"했더라도 마찬가지다 — pg_cron이 미활성이면
  (검증 안 됐지만) 마이그레이션이 조용히 성공하고 잡만 없거나, `db push`
  자체가 실패할 수 있다. 어느 쪽이든 이 쿼리로 확인한다.
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

`app/.env.example`을 복사해 `app/.env`를 만들어 채우는 방식도 가능. `app/.env`는
`app/.gitignore:14`의 `.env` 패턴으로 무시된다(`git check-ignore`로 확인함) —
운영 URL/anon key는 이미 `app/.env`에 들어가 있고 리포에는 커밋되지 않는다.

---

## 5. Auth 설정 (대시보드에서 확인/조정)

`config.toml`의 `[auth]` 값은 **로컬 스택 전용**이며 운영에는 적용되지 않는다.
운영 Auth 설정은 대시보드 Authentication에서 직접 맞춘다.

| 항목 | 로컬 `config.toml` 값 | 운영 (확인된 것 / 할 것) |
|---|---|---|
| 이메일 확인 | `enable_confirmations = false` | **운영은 이메일 확인 필수** — `auth/v1/settings`의 `mailer_autoconfirm = false` (2026-09-06 확인). 로컬과 정반대다. 따라서 앱의 `email_not_confirmed` 안내 카피 분기는 운영에서 **실제로 도달하는 경로**이므로 반드시 유지(P0-8 결정과 일치). 미확인 계정으로 로그인 시도하면 GoTrue가 이 에러를 던진다 |
| 회원가입 허용(`enable_signup`) | `true` | v0.1 공개 범위에 맞게 대시보드에서 확인 |
| 최소 비밀번호 길이 | `6` | 필요 시 상향 |
| 계정 열거 보호 | (config.toml에 항목 없음) | 대시보드에 해당 토글이 있으면 상태 확인. `config.toml`로는 관리 불가 |
| SMTP | 로컬 캡처 서버 | **운영 SMTP 설정 필수** — 이메일 확인이 켜져 있으므로 가입 확인 메일이 실제로 나가야 신규 가입이 완료된다. SMTP 미설정이면 아무도 가입을 못 끝낸다 |

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

- [x] 운영 프로젝트 확보 — ref `cpaxqjqijrawmevzivwz`, region `ap-northeast-2`,
  URL/anon key 확보(`app/.env`). (2026-09-06)
- [x] 마이그레이션 16개 적용 — 경로 A(`supabase db push`)로 완료. 도중
  `20260820090012` 실패(§2 "실제로 이게 터진 사례") → `dc02bf9`로 고치고
  재적용해 통과. (2026-09-14)
- [ ] 0장 나머지 미확인 값: (d) 원격 PG 버전, (e) service_role 키 보관처.
- [x] 적용 후 검증 — `schema_migrations` 16행, public 테이블 7, RLS 정책 12,
  함수 20 확인. (2026-09-14)
- [ ] 보안 회귀 테스트 3종이 원격 DB 대상으로 PASS. (아직 미실행 — 마이그레이션
  적용 자체는 됐지만 이 항목은 별도 확인 필요)
- [x] **정리 경로가 살아 있다 — `docs/legal/privacy.html`의 "위치 이력 최대
  14일 보관" 약속이 실제로 지켜지는지가 이 항목 하나에 달려 있다.**
  `cron.job`에 `gyeote-location-history-retention` 행 존재·`active = true`
  확인됨(2026-09-14, [3장 잡 등록 확인](#cron-job-verify)).
- [ ] 앱 릴리즈 빌드에 운영 `SUPABASE_URL` / `anon` 키가 주입됐다(`service_role`
  키는 앱에 없음).
- [ ] 운영 SMTP 설정 완료(비밀번호 재설정 메일 발송 경로).
- [ ] 6장 스모크 체크 통과.
