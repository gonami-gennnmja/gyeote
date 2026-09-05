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
4. **상대 지도 표시** — A, B 둘 다 위치 권한 허용 → 서로의 위치가 지도에 뜨는지
5. **공유 끄면 사라지는지** — A가 공유를 off로 끄면, B의 화면에서 A가 사라지는지
   (반대 방향도 확인 — B가 꺼도 A 화면에서 B가 사라지는지)

5번이 제일 중요하다 — 이번 라운드 보안 수정(P0-8 이전, HIGH-2/C/D/F)이 전부 이
"끄면 안 보여야 한다" 계약을 지키기 위한 것이었고, SQL 레벨 회귀 테스트는
`supabase/tests/database/location_sharing_security.test.sql`로 이미 확인했지만
실기기에서 클라이언트가 그 결과를 제대로 반영해 그리는지는 여기서 처음 확인된다.

## 배포 완료 기준 — 방침 문구와 직결된 항목 (건너뛰지 말 것)

`supabase/DEPLOYMENT.md`의 "cron.job 행이 실제로 존재하는지 확인" 게이트는 성능/운영
편의 항목이 아니다. 개인정보처리방침에 "위치 이력은 14일간만 보관"이라고 적혀 있고,
그 문구가 사실이 되려면 `gyeote-location-history-retention` pg_cron 잡이 운영
프로젝트에 실제로 등록돼 있어야 한다. 이 확인을 건너뛰고 배포하면 방침 문구가
출시 첫날부터 허위 기재가 된다 — 앱 쪽 릴리즈 체크리스트가 다 끝나도 이 항목이
비어 있으면 출시하지 않는다.
