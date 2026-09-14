# 곁에 앱 릴리즈 런북 (v0.1, Android)

가인님이 자재(Supabase 값, Maps 키, 키스토어, 방침 확정본)를 주시는 시점부터 스토어
업로드까지 앱 쪽에서 밟는 순서다. 백엔드 배포(마이그레이션 적용, pg_cron 활성화 등)는
`supabase/DEPLOYMENT.md`를 따른다 — 여기서는 다루지 않는다.

이 문서의 명령은 전부 이번 QA 라운드에서 실제로 돌려서 통과를 확인한 것이다(추측 아님).
작업 디렉터리는 `app/`.

## 1. `.env` 채우기

```bash
cp .env.example .env
# SUPABASE_URL / SUPABASE_ANON_KEY 를 가인님이 주신 값으로 채운다
```

## 2. Maps 키 주입

v0.1은 Android 단독 출시다(iOS는 아직 프로젝트 스캐폴드가 없음 — v0.2). Android 쪽
주입 위치는 `android/local.properties`(gitignore됨, `flutter.sdk`/`sdk.dir` 등 이미
있는 파일에 한 줄 추가):

```bash
echo "MAPS_API_KEY=<Maps SDK 키>" >> android/local.properties
```

`android/app/build.gradle`이 이 값을 읽어 매니페스트 플레이스홀더로 주입한다. 값이
비어 있어도 빌드는 통과하고 지도만 회색으로 뜨므로, 이 단계를 빼먹으면 빌드 실패가
아니라 스모크 테스트에서 지도가 안 뜨는 걸로 뒤늦게 드러난다 — 순서대로 진행할 것.

주입이 실제로 됐는지는 빌드 후 `aapt2 dump xmltree <apk> --file AndroidManifest.xml`로
`com.google.android.geo.API_KEY`의 `android:value`가 `AIza`로 시작하는 실제 키인지
확인한다(`${MAPS_API_KEY}` 그대로면 안 읽힌 것).

### 2-1. Maps 키 제한 (Google Cloud 콘솔) — SHA-1 4종을 모두 등록

Maps 키는 반드시 "Android 앱" 제한을 걸어야 한다(패키지명 + 서명 인증서 SHA-1). 이때
등록해야 할 SHA-1이 **한 개가 아니다.** 빠뜨리면 "어떤 빌드에서는 지도가 뜨는데 다른
빌드에서만 안 뜨는" 형태로 터진다.

| # | 키 종류 | 언제 등록 가능 | 안 넣으면 |
|---|---|---|---|
| (a) | debug 키스토어 (개발자 각자 머신) | 지금. 각자 `keytool -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey` | 그 개발자의 로컬 debug 빌드에서 지도가 회색 |
| (b) | debug 키스토어 (CI/샌드박스) | 지금. 위와 같은 명령을 CI 환경에서 | CI 빌드 산출물로 지도 확인 불가 |
| (c) | 릴리즈 업로드 키스토어 | 실물 키스토어 수령 후. `keytool -list -v -keystore <업로드키.jks> -alias <alias>` | 로컬에서 만든 release 빌드에서 지도가 회색 |
| (d) | **Play 앱 서명 키** | **첫 AAB 업로드 후에야** Play Console → 설정 → 앱 서명에서 확인 가능 | **개발·내부 테스트에서는 지도가 뜨는데 스토어 배포판(프로덕션/공개 테스트)에서만 안 뜬다** |

`~/.android/debug.keystore`는 커밋되는 파일이 아니라 머신마다 첫 빌드 때 자동 생성되므로,
(a)와 (b)는 서로 다른 값이고 개발자가 늘어나면 계속 추가된다.

(d)가 이 목록에서 제일 위험하다 — Play App Signing을 쓰면 Play가 업로드 키로 받은 AAB를
자기 앱 서명 키로 **재서명**해서 배포한다. 그래서 사용자가 스토어에서 받는 APK의 서명
인증서는 (c) 업로드 키가 아니라 (d) Play 앱 서명 키다. (d)를 Maps 키 제한에 안 넣으면
릴리즈 당일 내부 테스트까지 다 통과해놓고 프로덕션 배포판에서만 지도가 회색으로 뜬다.
그런데 (d)는 첫 업로드를 해야 값이 생기므로, 릴리즈 당일 순서(아래 7절)에 명시적으로
넣어두지 않으면 반드시 빠진다.

## 3. `key.properties` 작성 (릴리즈 서명)

```bash
cp android/key.properties.example android/key.properties
# storePassword / keyPassword / keyAlias / storeFile(키스토어 절대경로) 채우기
```

키스토어가 아직 없으면 `key.properties.example` 안 주석의 `keytool -genkey ...`
명령으로 업로드 키를 새로 만든다. 이 파일이 없으면 release 빌드는 debug 키로
조용히 서명되며(빌드는 통과함) 스토어 업로드가 불가하다 — 아래 5번에서 이걸 걸러낸다.

## 4. 빌드

```bash
flutter pub get
flutter build appbundle
```

`build/app/outputs/bundle/release/app-release.aab`가 나온다. `flutter build apk --debug`로
먼저 한 번 훑어보고 싶으면 그래도 되지만(디버깅용, 3-ABI 미분리라 158MB대로 큼), 스토어에
올리는 건 AAB다.

## 5. 서명자 확인 (apksigner)

AAB 자체는 apksigner로 못 연다. bundletool로 설치 가능한 APK를 뽑아서 확인한다:

```bash
# bundletool-all 이 없으면: https://github.com/google/bundletool/releases 에서 최신 -all.jar 받기
java -jar bundletool-all.jar build-apks \
  --bundle=build/app/outputs/bundle/release/app-release.aab \
  --output=/tmp/app.apks \
  --ks=<key.properties의 storeFile> --ks-pass=pass:<storePassword> \
  --ks-key-alias=<keyAlias> --key-pass=pass:<keyPassword> \
  --mode=universal

unzip -o /tmp/app.apks -d /tmp/app_apks_extract
$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner verify --print-certs /tmp/app_apks_extract/universal.apk
```

출력의 `Signer #1 certificate DN`이 **debug가 아니라 실제 키스토어(3번에서 만든 alias)**
로 나와야 한다. `CN=Android Debug`가 보이면 `key.properties`가 안 읽힌 것이니 3번부터
다시 확인한다(경로 오타가 제일 흔한 원인).

참고로 이 시뮬레이션으로 실제 다운로드 크기도 같이 나온다(참고용, 확인 필수 아님):
`java -jar bundletool-all.jar get-size total --apks=/tmp/app.apks --dimensions=ABI,SCREEN_DENSITY`
— AAB 원본은 50~55MB대지만 Play 스플릿 배포로 기기당 실제 다운로드는 9MB대다.

## 6. 실기기 스모크 (두 계정, 순서대로)

에뮬레이터 말고 실기기 2대(또는 1대 + 다른 계정 2개)로 아래 순서를 통째로 한 번
따라간다 — 단위/위젯 테스트가 못 보는 "실제로 두 사람이 써봤을 때" 경로다.

1. **가입** — 계정 A, 계정 B 각각 회원가입
2. **그룹 생성** — A가 그룹 생성
3. **초대** — A가 초대 코드 발급 → B가 코드 입력해 참여
   - **[운영 첫 실측] 초대 코드 발급 자체가 성공하는지.** `create_relationship_invitation`이
     `extensions.gen_random_bytes`를 운영 DB에서 처음 실제로 호출하는 지점이다 — DDL
     적용(마이그레이션 16개 push)만으로는 이 경로가 한 번도 안 돌아봤다. **초대 코드
     발급이 실패하면 `gen_random_bytes`/`extensions` 스키마 권한(호출 역할에 `usage`/
     `execute` grant 있는지)부터 의심할 것** — 코드 로직 문제가 아니라 운영 확장·권한
     배선 문제일 가능성이 높다.
4. **상대 지도 표시** — A, B 둘 다 위치 권한 허용 → 서로의 위치가 지도에 뜨는지
   - **[운영 첫 실측] 위치가 실시간으로 갱신되는지 (앱 재시작·새로고침 없이).** B가
     지도를 켜둔 채로 A가 이동하거나 위치 핑을 재전송했을 때 지도가 자동으로
     갱신되는지 확인한다. 최초 1회 표시는 `get_peer_locations` REST 조회로도 되지만,
     이후 실시간 갱신은 `notify_location_ping()` 안에서 호출되는 `realtime.send()`
     브로드캐스트 경로를 타며, 이것도 DDL 적용만으론 검증 안 된 첫 실측 지점이다.
     **상대 위치가 처음엔 뜨는데 그 뒤로 실시간으로 안 움직이면 `realtime.send()` /
     `realtime.messages` RLS(Realtime Authorization)를 의심할 것.**
5. **공유 끄면 사라지는지** — A가 공유를 off로 끄면, B의 화면에서 A가 사라지는지
   (반대 방향도 확인 — B가 꺼도 A 화면에서 B가 사라지는지)

3번·4번의 두 표시 항목은 이번 라운드에 같은 부류(pg_cron 가드-true 경로, realtime
RLS 소유자 문제)로 두 번 데인 뒤에 넣었다 — **정적으로는 문제없어 보여도 "운영에서
실제로 처음 도는 경로"는 스모크에서 명시적으로 짚어두지 않으면, 실패했을 때 엉뚱한
데서 원인을 찾게 된다.** 지금 스모크 순서가 이미 이 경로들을 지나가긴 하지만, 증상과
용의자를 미리 적어둔 것과 안 적어둔 것의 디버깅 시간 차이가 크다.

5번이 제일 중요하다 — 이번 라운드 보안 수정(P0-8 이전, HIGH-2/C/D/F)이 전부 이
"끄면 안 보여야 한다" 계약을 지키기 위한 것이었고, SQL 레벨 회귀 테스트는
`supabase/tests/database/location_sharing_security.test.sql`로 이미 확인했지만
실기기에서 클라이언트가 그 결과를 제대로 반영해 그리는지는 여기서 처음 확인된다.

4번(지도 타일 실렌더)도 여기가 유일한 확인 지점이다 — CI/샌드박스에는 KVM도 GPU도
없어 에뮬레이터로 Google Maps GLES 렌더를 검증할 수 없다. 빌드 산출물에 키가 박혔는지
(2절)까지가 자동으로 확인 가능한 최대치이고, 실제로 타일이 그려지는지는 실기기 스모크
외에 방법이 없다.

## 7. 첫 AAB 업로드 후 — Play 앱 서명 키 SHA-1 등록 (건너뛰면 프로덕션에서만 지도 깨짐)

Play Console에 AAB를 처음 올리고 나면 → **설정 → 앱 서명**에서 "앱 서명 키 인증서"의
SHA-1이 생긴다. 이 값을 2-1절 표 (d)로 Google Cloud 콘솔의 Maps 키 제한(Android 앱
목록)에 추가한다.

이 단계는 스모크(6절)를 통과한 뒤, **프로덕션/공개 테스트 트랙으로 승격하기 전에**
한다. 내부 테스트 트랙까지는 (c) 업로드 키 서명이 그대로 쓰이는 경우가 있어 지도가
떠서 "다 됐다"고 착각하기 쉽지만, Play가 재서명해 배포하는 트랙에서는 (d) 없이는
지도가 회색이다. 릴리즈 당일 이 절을 건너뛰면 출시 후 사용자 신고로 알게 된다.

## 배포 완료 기준 — 방침 문구와 직결된 항목 (건너뛰지 말 것)

`supabase/DEPLOYMENT.md`의 "cron.job 행이 실제로 존재하는지 확인" 게이트는 성능/운영
편의 항목이 아니다. 개인정보처리방침에 "위치 이력은 14일간만 보관"이라고 적혀 있고,
그 문구가 사실이 되려면 `gyeote-location-history-retention` pg_cron 잡이 운영
프로젝트에 실제로 등록돼 있어야 한다. 이 확인을 건너뛰고 배포하면 방침 문구가
출시 첫날부터 허위 기재가 된다 — 앱 쪽 릴리즈 체크리스트가 다 끝나도 이 항목이
비어 있으면 출시하지 않는다.
