# 곁에 — Codemagic CI (iOS 빌드 경로)

이 저장소의 Android 빌드는 개발 환경(리눅스 컨테이너)에서 무료로 돈다
(`app/RELEASE_RUNBOOK.md`). 맥이 없어서 여기서 못 도는 건 iOS 빌드뿐이고,
**Codemagic 은 그 iOS 빌드 전용**으로 쓴다. 설정 파일은 저장소 루트
`codemagic.yaml`.

무료 플랜 = 월 500 macOS(M2) 분. 이 문서는 (1) 등록할 환경변수, (2) 무엇이
Apple 계정 대기인지, (3) 500분 안에서 언제 빌드를 돌릴지 정책을 다룬다.

---

## 1. Codemagic 에 등록할 환경변수

Codemagic 웹 UI → 앱 설정 → Environment variables 에서 **그룹**으로 묶어
등록한다(`codemagic.yaml` 의 `environment.groups` 가 이 그룹명을 참조한다).
**"Secure" 체크를 반드시 켠다** — 로그에 마스킹되고 값이 저장 후 안 보인다.

### 그룹 `gyeote_shared` (iOS·Android 공통)

| 변수명 | 내용 | 출처 |
|---|---|---|
| `SUPABASE_URL` | `https://cpaxqjqijrawmevzivwz.supabase.co` | `supabase/DEPLOYMENT.md` §0 / `app/.env` |
| `SUPABASE_ANON_KEY` | 운영 anon 키 | `app/.env` (커밋 안 됨). anon 키는 클라이언트 노출 전제지만 저장소엔 넣지 않는다 |

`.env` 는 `flutter_dotenv` 번들 에셋이라 빌드 전에 파일로 존재해야 한다 —
`codemagic.yaml` 첫 스크립트가 이 두 변수로 `app/.env` 를 만든다. 없으면
빌드가 **에셋 번들 단계에서** 실패한다(코드 문제 아님).

### 그룹 `gyeote_ios`

| 변수명 | 내용 | 지금 등록 가능? |
|---|---|---|
| `MAPS_API_KEY_IOS` | iOS 번들 ID 로 제한한 Google Maps SDK 키 | **가능** (가인님 발급). Android 키와 **별도 키**로 두는 게 표준 — 플랫폼별로 제한이 다르다 |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API 키 Issuer ID | ❌ 계정 대기 |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | 같은 API 키의 Key ID | ❌ 계정 대기 |
| `APP_STORE_CONNECT_PRIVATE_KEY` | 같은 API 키의 `.p8` 내용 전체 | ❌ 계정 대기 |

> `codemagic.yaml` 의 iOS 빌드 스크립트는 `APP_STORE_CONNECT_PRIVATE_KEY` 유무를
> 보고 자동 분기한다 — 없으면 **서명 없는 컴파일 검증**(`flutter build ios
> --no-codesign`), 있으면 **서명 IPA 빌드**. 즉 위 3개를 지금 비워둬도 워크플로는
> 돌아간다(단 아래 2절의 스캐폴드 블로커는 별개).

App Store Connect API 키는 계정 연동 후 App Store Connect → Users and Access →
Integrations → App Store Connect API 에서 발급한다. Codemagic 은 이 세 값을
"App Store Connect" 통합으로 등록하는 방식도 지원하며, 그 경우 `codemagic.yaml`
의 `publishing.app_store_connect.auth: integration` 주석을 풀면 된다.

### 그룹 `gyeote_android` (예비 워크플로용, 지금은 안 써도 됨)

| 변수명 | 내용 |
|---|---|
| `MAPS_API_KEY_ANDROID` | Android 패키지명+SHA-1 로 제한한 Maps 키 |
| Android code signing | Codemagic UI 의 "Android code signing" 에 업로드 키스토어(.jks) + 비밀번호 + alias 등록 → `CM_KEYSTORE_PATH` / `CM_KEYSTORE_PASSWORD` / `CM_KEY_PASSWORD` / `CM_KEY_ALIAS` 가 자동 주입됨. 워크플로 스크립트가 이걸로 `android/key.properties` 를 만든다 |

Android 서명 SHA-1 은 `app/RELEASE_RUNBOOK.md` 2-1절 참고(4종 다 등록).

---

## 2. Apple Developer 계정 대기 항목 (오늘 결제 → 전파 중)

iOS 워크플로가 **실제로 성공하려면 두 가지 블로커가 각각 풀려야 한다.** 둘은
별개다.

### 블로커 A — iOS Xcode 스캐폴드 (담당: Diana, 계정과 무관)

지금 `app/ios/` 에는 `Podfile`, `Runner/AppDelegate.swift`, `Runner/Info.plist`,
`Flutter/Maps.xcconfig.example` 만 있고 **`Runner.xcodeproj` / `Runner.xcworkspace`
가 없다.** 이게 없으면 `flutter build ios` 가 프로젝트를 못 찾아 즉시 실패한다
(`codemagic.yaml` 의 CocoaPods 스텝이 이걸 감지해 명시적으로 멈춘다).

Diana 의 스캐폴드에 포함돼야 할 것:
- `Runner.xcodeproj` (+ `project.pbxproj`), `Runner.xcworkspace`
- `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` — 각각 `#include "Generated.xcconfig"`
  **와 `#include "Maps.xcconfig"`**. 후자가 있어야 `Info.plist` 의
  `$(MAPS_API_KEY)` 가 치환된다(`Maps.xcconfig.example` 주석 참고)
- `Runner/Base.lproj/LaunchScreen.storyboard`, `Main.storyboard`
- `Runner/Assets.xcassets` (앱 아이콘 — Din 소스에서 생성)
- `Runner/Runner-Bridging-Header.h` (필요 시)

**블로커 A 만 풀리면**(계정 없이도) Codemagic iOS 워크플로가 `flutter build ios
--release --no-codesign` 까지 통과한다 — Swift 컴파일, 팟 링크, GoogleMaps SDK
링크, Info.plist·xcconfig 배선, 에셋 카탈로그가 전부 검증된다. 아카이브 직전
단계까지가 여기서 확인 가능한 최대치다.

### 블로커 B — 서명·배포 (계정 연동 필요)

계정이 활성화되고 아래가 갖춰지면 서명 IPA + TestFlight 업로드가 열린다:
- Apple Developer 포털에 App ID `com.gyeote.app` 등록
- App Store Connect 에 앱 레코드 생성 (→ 숫자 Apple ID 를 `codemagic.yaml` 의
  `APP_STORE_APPLE_ID` 에 채움)
- App Store Connect API 키 발급 → 1절 `gyeote_ios` 의 3개 변수 등록
- `codemagic.yaml` 의 `publishing:` 블록 주석 해제
- 배포 인증서 / 프로파일: Codemagic 이 API 키로 자동 관리(`fetch-signing-files
  --create`)하게 두거나, 수동 업로드

계정 대기 중 할 수 있는 것: 위 목록을 미리 읽고, 번들 ID `com.gyeote.app` 이
Android `applicationId` 와 일치하는지 확인(일치함), Info.plist 의 권한 문구
(`NSLocationWhenInUseUsageDescription`) 심사 대비 문구 검토 — 이미 반영됨.

---

## 3. 500분/월 운영 정책

### iOS 빌드 1회 소요 추정 (`mac_mini_m2`)

| 단계 | 콜드 | 캐시 |
|---|---|---|
| Flutter 3.47.1 준비 | 1~3분 (Codemagic 이 이 버전을 모르면 git 체크아웃) | ~20초 |
| `flutter pub get` | ~40초 | ~20초 |
| `flutter analyze` + `flutter test` (95개) | ~2.5분 | ~2분 |
| `pod install` (GoogleMaps SDK 포함) | 2~4분 | ~1분 |
| `flutter build ipa --release` (또는 `--no-codesign`) | 12~18분 | 6~10분 |
| 서명 + IPA export | 1~2분 | 1~2분 |
| TestFlight 업로드 | 2~5분 | 2~5분 |
| **합계** | **약 22~35분** | **약 13~20분** |

→ **평균 20분/빌드로 잡으면 500분 ≈ 월 25회.** 콜드 빌드·재시도 감안하면
**실사용 20회 안팎(대략 1.5일에 1회)**. 매 커밋마다 도는 건 불가능하고 불필요.

### 트리거 조건 (매 커밋 금지)

`codemagic.yaml` 에 이미 반영:

1. **`v*` 태그 push 에만** iOS 워크플로 실행 — 릴리즈 후보(`v0.1.0-rc1`, `v0.1.0` 등).
   일반 브랜치 push / PR 에는 **안 돈다.**
2. **수동 실행** — Codemagic UI 의 "Start new build" 로 언제든.
3. **(권장, 별도 등록) 월 1회 스케줄 빌드** — `codemagic.yaml` 이 아니라 Codemagic
   UI 의 "Build triggers → Schedule" 로 매월 1일 1회. Xcode/CocoaPods/Flutter 가
   조용히 올라가서 iOS 만 깨지는 걸 릴리즈 당일이 아니라 미리 잡는 드리프트
   보험(월 20분).

**안 하는 것**: PR 마다, `app/lib/**` 변경마다, main push 마다. Dart/Flutter
레이어 회귀는 무료로 도는 Android CI + 로컬 `flutter analyze`/`flutter test` 가
이미 커버한다. iOS 고유 회귀(팟 해석, Swift 컴파일, Info.plist, 서명)는
릴리즈 후보 주기로 확인해도 충분하다.

### 예상 월 사용량 (이 정책 기준)

| 항목 | 횟수 | 분 |
|---|---|---|
| 릴리즈 후보 태그 빌드 | 2~4 | 40~80 |
| 월 1회 드리프트 스케줄 | 1 | ~20 |
| 수동 디버그 빌드 | 2~3 | 40~60 |
| **합계** | | **약 100~160분** |

500분 대비 여유가 크다 — 나쁜 달(재시도, 서명 삽질)에도 한도 안에 든다.
Android 예비 워크플로(`android-appbundle`)는 자동 트리거가 없어 수동으로만
돌고, 평소엔 개발 환경 무료 빌드를 쓰므로 분을 먹지 않는다.

---

## 4. Diana 스캐폴드가 들어오면 (Tom 후속 작업)

블로커 A 해소되면 QA 가 실제로 붙여볼 것:
1. 로컬에서 `flutter build ios --release --no-codesign` 이 되는지 (맥 없으면
   불가 — 그 경우 Codemagic 수동 빌드로 확인)
2. `codemagic.yaml` 의 CocoaPods 감지 스텝이 통과하는지
3. `Maps.xcconfig` → `Info.plist` `$(MAPS_API_KEY)` → 빌드 산출물의
   `MapsApiKey` 값이 실제 키로 치환됐는지 (Android 에서 `aapt2` 로 했던 것과
   동일한 검증을 `.app/Info.plist` 에 대해)
4. 그 결과로 이 문서 2절 블로커 A 를 "해소"로 갱신
