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

## 2. 블로커 현황

iOS 워크플로가 **실제로 성공하려면 두 가지 블로커가 각각 풀려야 한다.** 둘은
별개다. 2026-09-07 기준 **블로커 A 해소, 블로커 B 대기**(Apple Developer 결제 →
전파 중). 지금 첫 빌드를 돌리면 강등 모드(no-codesign)로 A 까지 검증된다.

### 블로커 A — iOS Xcode 스캐폴드 — ✅ 해소됨 (2026-09-07, 커밋 `34e0e8f` + `cf375b1`)

`flutter create --platforms=ios` 로 스캐폴드가 들어왔다. QA 가 Linux 에서 확인
가능한 범위까지 사전 점검한 결과(맥이 없어 컴파일 자체는 Codemagic 첫 실행에서
검증):

| 항목 | 상태 |
|---|---|
| `Runner.xcodeproj` / `Runner.xcworkspace` | 있음 |
| `Debug.xcconfig` / `Release.xcconfig` | `#include "Generated.xcconfig"` + `#include? "Maps.xcconfig"` (옵셔널 include — Maps.xcconfig 없어도 빌드 통과, 지도만 회색) |
| `Info.plist` | `MapsApiKey = $(MAPS_API_KEY)`, `NSLocationWhenInUseUsageDescription`(한글), `UIApplicationSceneManifest`. `NSLocationAlwaysAndWhenInUseUsageDescription` 없음(의도) |
| `AppDelegate.swift` | 3.47 새 템플릿(`FlutterImplicitEngineDelegate`) + `GMSServices.provideAPIKey` 블록. `mapsApiKey != "$(MAPS_API_KEY)"` 미치환 가드 있음 |
| pbxproj 번들 ID | `com.gyeote.app` (RunnerTests 는 `com.gyeote.app.RunnerTests`) — Android `applicationId` 와 일치 |
| pbxproj 배포 타겟 | `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `Podfile` `platform :ios, '15.0'` — 일치 (현행 GoogleMaps SDK 요구치) |
| `AppIcon.appiconset` | 전 사이즈 + `Contents.json` (알파 제거된 iOS 세트) |
| `pubspec.lock` | `meta 1.18.3` / `vector_math 2.4.0` 으로 정정됨 — Flutter 3.47.1 SDK 고정값과 일치. `flutter pub get` 재실행해도 lock 안 바뀜(고정 안정) |
| `flutter analyze` / `flutter test` | 7 issues·0 error / **98/98 통과** (Linux 에서 확인) |

**아직 검증 못 한 것(= Codemagic 첫 실행이 확인해야 할 것):** Swift 컴파일,
`pod install` (GoogleMaps SDK 해석), GoogleMaps SDK **링크**, `Info.plist` 의
`$(MAPS_API_KEY)` 치환이 실제 빌드 산출물에 반영되는지, 에셋 카탈로그 컴파일.
이건 맥이 필요해 QA 환경에서 못 하고, 아래 5절대로 가인님이 Codemagic 을
연결해 첫 빌드를 돌려야 나온다.

**캐시로 인한 옛 lock 물림 걱정 없음:** 현재 `codemagic.yaml` 은 의존성
캐시(`cache:` 블록)를 켜지 않았다. 그래서 매 빌드가 완전 콜드이고 `flutter pub
get` / `pod install` 이 항상 커밋된 `pubspec.lock` / `Podfile.lock` 기준으로
새로 푼다. 나중에 캐시를 켜면 캐시 키에 lock 해시를 포함시켜야 한다.

### pbxproj 서명 설정 — 계정 연동 시 손봐야 할 것

pbxproj 는 `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY[sdk=iphoneos*] =
"iPhone Developer"` 인데 **`DEVELOPMENT_TEAM` 이 비어 있다.** `--no-codesign`
빌드는 xcodebuild 에 `CODE_SIGNING_ALLOWED=NO` 를 넘겨 이걸 우회하므로 강등
모드에는 문제없다. 계정 연동 후 서명 빌드에서는 `codemagic.yaml` 의
`xcode-project use-profiles` 가 프로파일·팀을 프로젝트에 주입하므로 pbxproj 를
직접 고칠 필요는 없지만, 안 되면 `DEVELOPMENT_TEAM` 을 Codemagic 환경변수로
넣거나 pbxproj 에 박는 걸 검토한다(블로커 B 처리 시).

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

> ⚠️ 위 표는 **추정치**다(맥이 없어 QA 가 실측 못 함). 첫 Codemagic 실행이
> 콜드 빌드이므로, 그 빌드의 실제 소요 시간(Codemagic UI 의 각 스텝 duration)을
> 이 표에 반영해 예산 계획을 교정한다 — 특히 `flutter build` 스텝과 `pod
> install` 스텝. 첫 빌드 결과가 나오면 이 표를 실측으로 대체할 것.

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

## 4. 강등 모드(no-codesign) 첫 빌드에서 확인할 것

블로커 A 는 해소됐고 블로커 B(Apple 계정)는 아직이므로, 첫 빌드 목표는
**강등 모드 통과**다. Codemagic 실행 후 로그·산출물에서 확인:

1. CocoaPods 스텝: `ios/Runner.xcodeproj` 감지 통과 → `pod install` 이 GoogleMaps
   관련 팟(`GoogleMaps`, `Google-Maps-iOS-Utils` 등)을 해석하는지
2. 빌드 스텝: `APP_STORE_CONNECT_PRIVATE_KEY` 가 없으니 `flutter build ios
   --release --no-codesign` 분기로 들어가 **Swift 컴파일 + GoogleMaps SDK 링크**
   가 통과하는지 (링크 실패가 이 단계의 가장 흔한 사고)
3. 산출물 `build/ios/iphoneos/Runner.app` 이 나오는지, 그 안 `Info.plist` 의
   `MapsApiKey` 가 `$(MAPS_API_KEY)` 그대로가 아니라 실제 키로 치환됐는지
   (Android 에서 `aapt2` 로 했던 검증의 iOS 판 — `plutil -p Runner.app/Info.plist`)
4. `flutter analyze` / `flutter test` 게이트가 맥 러너에서도 통과하는지
5. **각 스텝 소요 시간을 3절 표에 실측으로 반영**

이게 다 통과하면 남은 건 블로커 B(서명 인증서·프로파일·IPA export·TestFlight)
뿐이고, 계정만 붙으면 `codemagic.yaml` 이 자동으로 서명 분기로 넘어간다.

---

## 5. 첫 Codemagic 빌드 트리거 (가인님 — QA 는 계정·연결 권한 없음)

QA 세션에는 Codemagic 계정도 저장소 연결 권한도 없고 맥도 없어서, 아래는
가인님이 직접 한다.

1. **저장소 연결**: codemagic.io 로그인 → Add application → 이 저장소 선택 →
   "codemagic.yaml" 설정 방식 선택 (UI 워크플로 편집기 아님)
2. **환경변수 그룹 3개 생성** (1절 표대로). 지금 당장은 `gyeote_shared` +
   `gyeote_ios` 의 `MAPS_API_KEY_IOS` 까지만 있으면 강등 모드가 돈다.
   App Store Connect 3개 변수는 비워둔다 → 스크립트가 알아서 no-codesign 으로 감
3. **첫 빌드 실행**: 두 방법 중 하나
   - `git tag v0.1.0-rc0 && git push origin v0.1.0-rc0` → `ios-testflight` 자동 실행
   - 또는 Codemagic UI 에서 `ios-testflight` 워크플로 "Start new build" (브랜치 지정)
4. **결과 공유**: 빌드 성공/실패 + 각 스텝 duration 을 QA 에게 → 4절 검증 항목
   대조 + 3절 표 실측 교정
5. 강등 모드 통과 확인되면, 계정 전파 완료 후 블로커 B(2절) 진행
