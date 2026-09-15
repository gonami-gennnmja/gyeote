# 초대 딥링크 — 웹 쪽 설계 (v0.2) + SNS 공유 확장 (v0.3 티켓)

Din 작성, 2026-09-15. 범위: 가인님 지시대로 **웹 쪽만** — iOS/Android 앱의
Associated Domains 엔타이틀먼트·인텐트 필터·`app_links` 패키지 연동 같은
**앱 쪽 딥링크 처리는 별도 티켓**(Diana/Dexa)이다. 이 문서는 iyyko.com에
뭘 놓아야 하는지, 그리고 왜 그 경로인지를 정한다.

관련 문서: 개인정보처리방침 게시(`v0.1-release-assets.md` §3-4)에서 GitHub
Pages + 커스텀 서브도메인(`privacy.iyyko.com`) 절차를 이미 썼다 — 이번에도
같은 방식(무료, 정적 파일만)을 쓴다.

---

## 1. 도메인/경로 설계

### 1-1. 결정: 전용 서브도메인 `link.iyyko.com`

| 후보 | URL 형태 | 판단 |
|---|---|---|
| **A. 서브도메인 `link.iyyko.com` (권장)** | `https://link.iyyko.com/invite/ABC123` | GitHub Pages 커스텀 도메인은 **한 저장소당 하나**만 붙는다. `privacy.iyyko.com`이 이미 이 저장소(`gyeote`)의 `gh-pages` 브랜치를 쓰고 있으므로, 딥링크 인프라는 **새 저장소**(예: `gyeote-links`)를 하나 더 만들어 별도 서브도메인에 붙인다. DNS는 CNAME 레코드 하나만 추가하면 되고(privacy와 동일한 방식), apex 도메인을 나중에 다른 용도(마케팅 랜딩 페이지 등)로 남겨둘 수 있다. |
| B. apex `iyyko.com` | `https://iyyko.com/invite/ABC123` | 링크가 더 짧고 "iyyko.com에 놓는다"는 가인님 원 표현과 더 가깝다. 다만 apex를 GitHub Pages에 붙이려면 CNAME이 아니라 **A/ALIAS 레코드**가 필요하고(DNS 설정이 한 단계 더 있음), 나중에 iyyko.com 자체를 제품 랜딩 페이지로 쓰고 싶어지면 딥링크 인프라와 충돌한다. |

**A로 확정.** apex를 선호하시면 절차는 1-4에 병기해뒀다 — DNS 레코드
종류만 다르고 나머지는 동일하다.

### 1-2. 경로

- **캐노니컬**: `/invite/<코드>` — 예: `https://link.iyyko.com/invite/ABC123`.
- 짧은 alias(`/i/<코드>`)는 이번엔 안 만든다 — 관리 대상이 늘고, 공유
  링크 길이 차이가 실사용에서 크지 않다. 나중에 필요해지면 `/i/` →
  `/invite/`로 정적 리다이렉트 페이지 하나 추가하면 된다.
- iOS `paths`와 Android `intent-filter`의 host/path 패턴은 위 경로와
  정확히 맞춰야 한다(3장 참고).

---

## 2. `.well-known` 파일 — 지금 만들 것 / 나중에 채울 것

두 파일 다 `link.iyyko.com`의 **`/.well-known/`** 아래에 놓는다
(앱이 이 경로를 HTTPS로 직접 가져가 검증한다 — 리다이렉트 있으면 실패).

### 2-1. `apple-app-site-association` (확장자 없음, iOS)

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.com.gyeote.app",
        "paths": ["/invite/*"]
      }
    ]
  }
}
```

- `TEAMID`는 Apple Developer 계정의 **Team ID**(10자리 영숫자,
  developer.apple.com/account → Membership에서 확인). 가인님이 Apple
  계정 결제를 이미 하셨으니 지금 확인 가능 — **이건 지금 채울 수 있다.**
- 확장자가 없는 파일이라 GitHub Pages가 `application/json`으로 안 내려줄
  수 있다(정확한 Content-Type 대신 `text/plain`이나 `octet-stream`으로
  서빙될 가능성 — Jekyll이 확장자 없는 파일을 만지지 않도록 저장소 루트에
  `.nojekyll`을 반드시 둔다, `privacy.html` 배치 때와 동일). Apple의 실제
  검증기는 Content-Type에 관대한 편이라 GitHub Pages로 서빙하는 사례가
  흔하지만, **배포 후 반드시 실측**한다:
  ```
  curl -I https://link.iyyko.com/.well-known/apple-app-site-association
  ```
  헤더가 이상하거나 Universal Link가 실제로 안 열리면, 이 파일만 Cloudflare
  Pages/Workers 같은 헤더 제어 가능한 호스팅으로 옮기는 걸 대안으로 남겨둔다
  (그때도 도메인은 `link.iyyko.com` 그대로 유지 가능 — DNS만 바뀜).

### 2-2. `assetlinks.json` (Android)

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.gyeote.app",
      "sha256_cert_fingerprints": [
        "PLACEHOLDER_FILL_AFTER_FIRST_AAB_UPLOAD"
      ]
    }
  }
]
```

- `.json` 확장자라 GitHub Pages가 `application/json`을 정확히 내려준다
  (2-1 같은 우려 없음).
- **`sha256_cert_fingerprints`는 지금 못 채운다 — 언제, 어디서 채우는지:**
  1. Play Console에 **첫 AAB를 업로드**한다(내부 테스트 트랙이어도 된다 —
     프로덕션까지 안 가도 서명 키는 이 시점에 생긴다).
  2. Play Console → 해당 앱 → **설정(Setup) → 앱 무결성(App integrity) →
     앱 서명(App signing)** 으로 들어간다.
  3. **"앱 서명 키 인증서"(App signing key certificate)** 섹션의
     **SHA-256 인증서 지문**을 복사한다.
     ⚠️ **"업로드 키 인증서"(Upload key certificate)가 아니다** — Play
     App Signing(기본값, 권장 설정)을 쓰면 사용자에게 실제로 배포되는
     APK/AAB는 Play가 관리하는 **서명 키**로 서명되고, 우리가 로컬에서
     갖고 있는 keystore는 Play에 올리기 위한 **업로드 키**일 뿐이다.
     `assetlinks.json`은 "실제 배포되는 앱이 이 지문으로 서명돼 있다"를
     검증하는 파일이므로 **서명 키 쪽 지문**을 써야 한다. 업로드 키
     지문을 넣으면 검증이 항상 실패한다.
  4. 위 placeholder를 그 값으로 교체해 커밋·재배포.
- 이 파일이 완성되기 전까지는 Android에서 **Universal/App Link 자동
  열기가 검증되지 않는다** — 링크를 눌러도 앱이 안 열리고 브라우저로 가는
  정도지 다른 게 깨지진 않는다(4장 폴백 페이지가 정상적으로 뜬다). 즉
  **이 지문이 없어도 출시 자체는 막히지 않는다** — 다만 "링크 누르면 앱이
  바로 열리는" 경험은 AAB를 한 번 업로드해서 지문을 채울 때까지 못 켠다.

---

## 3. 앱 쪽에 필요한 것 (요약만 — 별도 티켓)

- **iOS**: `Runner.entitlements`에 `com.apple.developer.associated-domains`
  = `["applinks:link.iyyko.com"]` 추가 + Xcode Signing & Capabilities에서
  Associated Domains capability 켜기.
- **Android**: `AndroidManifest.xml`의 `MainActivity`에
  `<intent-filter android:autoVerify="true">`로 `link.iyyko.com`/`/invite/`
  호스트·경로 패턴 추가.
- **Flutter**: URL을 받아서 라우팅하는 처리(예: `app_links` 패키지)가
  필요하고, 앱이 받은 코드를 `invitation_accept_screen`에 바로 넘기는
  연결까지 있어야 "링크 클릭 → 앱에서 미리보기" 경험이 완성된다.
- **부수 효과(Diana 참고)**: `group_detail_screen.dart`의 초대 코드 복사
  버튼("복사하고 닫기")이 지금은 **코드만** 클립보드에 넣는다. 딥링크가
  생기면 `https://link.iyyko.com/invite/<코드>` **전체 URL**을 복사하도록
  바꿔야 카카오톡/문자 등에 붙여넣었을 때 실제로 클릭 가능한 링크+ 미리보기
  카드가 뜬다(6장에서 이 미리보기 품질을 다룬다). 코드만 복사하는 지금
  동작은 앱 안에서 수동 입력할 땐 맞지만, 링크 공유 맥락엔 안 맞다.

이 문서(웹 쪽)만으로는 아무것도 안 열리지 않는다 — 위 앱 쪽 작업과 세트로
묶여야 기능이 완성된다는 걸 Plexa 배분 시 같이 안내해달라.

---

## 4. 폴백 페이지 — 앱이 없을 때 도착하는 화면

### 4-1. 동작 원리 (정적 호스팅 트릭)

GitHub Pages는 서버 라우팅이 없다. `/invite/ABC123`, `/invite/XYZ999`처럼
코드마다 다른 URL이 실제 파일로 존재할 수 없으므로, **커스텀
`404.html`을 폴백 페이지로 쓴다** — GitHub Pages는 존재하지 않는 경로
요청 시 저장소 루트의 `404.html`을 돌려준다(HTTP 상태는 404지만 브라우저는
그 내용을 정상적으로 렌더링한다 — 사용자에게는 안 보이고, 정적 호스팅에서
경로 파라미터를 다루는 표준적인 방법이다). 그 페이지의 JS가
`location.pathname`을 파싱해 코드를 꺼내 보여준다.

앱이 설치돼 있으면 이 페이지는 아예 안 뜬다 — OS가 Universal/App Link로
가로채 앱을 바로 연다. 이 페이지는 **앱이 없거나(2장 파일 미검증 포함)
검증에 실패했을 때만** 보인다.

### 4-2. 상태 두 가지 (스토어 등재 전 / 후)

같은 페이지 안에 **불린 상수 하나**(`const STORE_LIVE = false;`)로 전환한다
— 스토어 등재되면 이 값만 `true`로 바꿔 재배포.

**A. `STORE_LIVE = false` (지금)**
- 제목: "곁에가 곧 출시돼요"
- 본문: "이 초대 코드를 저장해두세요. 앱이 출시되면 로그인 후 이 코드를
  입력해서 그룹에 들어올 수 있어요."
- 코드 큰 글씨(모노스페이스) + "복사" 버튼(Clipboard API)
- 스토어 배지는 회색조/비활성 톤으로 "준비 중" 표시(링크는 아직 안 검)

**B. `STORE_LIVE = true` (스토어 등재 후)**
- 제목: "곁에 앱에서 초대를 확인하세요"
- 본문: "앱이 설치돼 있으면 자동으로 열렸을 거예요. 안 열렸다면 아래에서
  설치한 뒤 로그인하고, 이 코드를 입력해주세요."
- 코드 + 복사 버튼(동일)
- App Store / Google Play 배지 — 실제 스토어 URL로 연결(둘 다 항상 노출,
  User-Agent로 하나만 보여주는 자동 분기는 오탐 리스크가 있어 이번엔 안 함)

### 4-3. 카피(해요체, 189ae2c 기준과 동일 톤)

| 요소 | A(출시 전) | B(출시 후) |
|---|---|---|
| 제목 | 곁에가 곧 출시돼요 | 곁에 앱에서 초대를 확인하세요 |
| 본문 | 이 초대 코드를 저장해두세요. 앱이 출시되면 로그인 후 이 코드를 입력해서 그룹에 들어올 수 있어요. | 앱이 설치돼 있으면 자동으로 열렸을 거예요. 안 열렸다면 아래에서 설치한 뒤, 로그인하고 이 코드를 입력해주세요. |
| 코드 없이 접속(경로 파싱 실패) | "초대 코드를 찾을 수 없어요. 링크를 다시 확인해주세요." | 동일 |

### 4-4. 디자인

`docs/legal/privacy.html`과 같은 언어로 만든다 — 인라인 CSS, 단일 파일,
브랜드는 로고 2B(인디고 `#3B4272` 배경, 흰/크림 텍스트, 다크 변형 마크를
상단에 작게). 코드 표시 박스는 카드형으로 크고 또렷하게(복사가 핵심
행동이므로).

### 4-5. 미리보기 강화(선택, 지금 안 함)

`get_invitation_preview` RPC로 "OO님이 초대했어요"까지 폴백 페이지에서
보여주고 싶을 수 있는데, 이 RPC는 현재 `authenticated` 역할에만
`grant execute`돼 있어(P0-8 관련 마이그레이션) **익명 방문자는 호출 못
한다.** anon 권한을 열어주는 건 백엔드 판단(Dexa)이 필요한 별도 변경이라
이번 범위에서 안 한다 — 지금은 코드만 보여주는 걸로 충분하다.

---

## 5. 배치 절차 (privacy.html과 동일한 방식)

1. 새 저장소 생성(예: `gyeote-links`), 다음 파일을 루트에 둔다:
   - `.well-known/apple-app-site-association` (확장자 없음, 2-1 내용)
   - `.well-known/assetlinks.json` (2-2 내용, SHA-256은 placeholder)
   - `404.html` (4장 폴백 페이지)
   - `.nojekyll` (빈 파일 — Jekyll이 `.well-known/`이나 확장자 없는 파일을
     건드리지 않게)
   - `CNAME` (내용 한 줄: `link.iyyko.com`)
2. GitHub → 그 저장소 Settings → Pages → Source = 기본 브랜치(`main`),
   `/ (root)`.
3. DNS(가인님): `link` 서브도메인에 CNAME 레코드 → `<계정>.github.io`.
4. Pages → Custom domain에 `link.iyyko.com` 입력, DNS 확인되면
   **Enforce HTTPS** 켠다(AASA·assetlinks.json 둘 다 HTTPS 필수).
5. 배포 후 `curl -I` 로 두 `.well-known` 파일이 200으로 내려오는지,
   `404.html`이 실제로 코드 페이지로 보이는지 확인.

**apex(`iyyko.com`)를 원하시면**: 3번 DNS를 CNAME 대신 GitHub가 문서화한
apex용 A 레코드 4개(+ 선택적으로 AAAA)로 바꾸고, 나머지 절차는 동일.
`privacy.html`을 쓰는 저장소와는 별개 저장소로 유지해야 한다(한 저장소 =
한 커스텀 도메인).

---

## 6. v0.3 티켓 — SNS 공유 확장 (조사만, 구현 안 함)

가인님이 추후 확장으로 원하신 것. 카카오톡·인스타그램 등에 초대 링크를
공유할 때 필요한 것을 조사해 정리한다.

### 6-1. 핵심 발견 — 4장의 폴백 페이지에 OG 태그만 제대로 넣으면 절반은 끝난다

카카오톡 채팅에 URL을 붙여넣거나, iMessage/문자, X(Twitter) 등 "일반
링크 미리보기"를 지원하는 대부분의 채널은 **표준 Open Graph 메타 태그**를
읽어서 카드형 미리보기를 만든다. 이건 **앱 코드를 전혀 안 건드리고**
4장 폴백 페이지의 `<head>`에 태그 몇 줄만 추가하면 된다:

```html
<meta property="og:type" content="website">
<meta property="og:site_name" content="곁에">
<meta property="og:title" content="곁에 초대장이 도착했어요">
<meta property="og:description" content="OO님이 위치를 함께 나누자고 초대했어요.">
<meta property="og:image" content="https://link.iyyko.com/og/invite-default.png">
<meta property="og:url" content="https://link.iyyko.com/invite/ABC123">
<meta name="twitter:card" content="summary_large_image">
```

`Share.share(url)`(Flutter `share_plus` 패키지)로 OS 공유 시트를 띄우면
사용자가 카카오톡이든 문자든 뭘 고르든 **이 메타 태그가 자동으로
써먹힌다** — 카카오 전용 SDK 없이도 "일반 링크 공유"는 이미 동작한다.

### 6-2. 플랫폼별 실제 제약 (여기서부터가 v0.3에서 결정할 부분)

| 채널 | 동작 방식 | 필요한 것 | 비용/난이도 |
|---|---|---|---|
| **카카오톡(기본)** | 채팅에 URL 붙여넣기 → OG 태그로 카드 생성 | 6-1의 OG 태그만 | 낮음(4장에 태그 추가만) |
| **카카오톡(고급 — Kakao Link)** | "카카오톡 공유하기" 버튼으로 커스텀 카드(버튼 2개, 앱 실행 딥링크 등) | Kakao Developers 앱 등록(JS/네이티브 앱 키), "메시지 템플릿" 제작, Android는 키 해시, iOS는 번들ID 등록. 앱에 Kakao SDK 연동 | 중간 — 별도 개발 티켓 |
| **iMessage/문자(iOS)** | 링크 자동 미리보기(LinkPresentation) | OG 태그만 | 낮음 |
| **X(Twitter)** | `twitter:card` 메타(OG 폴백 가능) | `twitter:card`/`twitter:title` 등 추가 | 낮음 |
| **인스타그램 DM** | 링크 붙여넣기 시 OG 기반 미리보기 | OG 태그만 | 낮음 |
| **인스타그램 스토리(네이티브 공유)** | 피드/캡션엔 링크가 클릭 안 됨 — 스토리 "스티커"로 공유하려면 인스타그램 앱에 **이미지**를 직접 전달(iOS `instagram-stories://share` URL 스킴 + pasteboard로 배경 이미지 전달, Android는 별도 Intent) | 네이티브 플랫폼 채널 작업(공식 Flutter 패키지 없음, 커스텀 구현 또는 서드파티 플러그인) + 배경 이미지 1080×1920 생성 로직 | 높음 — 별도 개발 티켓, 우선순위 낮음 권장 |

### 6-3. OG 이미지 스펙

- **범용 안전 사이즈**: `1200×630`(비율 1.91:1) — 카카오톡·페이스북·
  X `summary_large_image`·iMessage 대부분 커버.
- 형식 PNG/JPG, 1MB 이하 권장(로딩 지연·캐시 실패 방지), HTTPS 절대경로
  필수.
- **1차(v0.3 시작)**: 초대자 이름 없이 고정 이미지 1장(로고 2B 브랜드 +
  "곁에" 워드마크 + "초대장이 도착했어요" 같은 범용 문구). 제작 비용 거의
  0 — Din이 `feature_graphic.png`와 같은 방식으로 SVG→PNG 렌더 가능.
- **2차(나중)**: 초대자 닉네임을 이미지에 넣는 **동적 OG 이미지**
  ("민지님이 초대했어요"). 정적 호스팅으로는 못 만든다 — 서버가 요청마다
  이미지를 그려줘야 하므로 Supabase Edge Function이나 Vercel OG Image
  같은 렌더링 서버가 필요하다. 효과는 크지만(개인화된 미리보기가 클릭률을
  확실히 올림) 인프라가 하나 늘어나는 작업이라 1차보다 뒤로 미룬다.

### 6-4. v0.3 티켓 요약

1. **(저비용, 먼저)** 4장 폴백 페이지에 OG/Twitter Card 메타 태그 + 고정
   OG 이미지(1200×630) 추가. `share_plus`로 앱에 "초대 링크 공유하기"
   버튼 추가(그룹 상세 화면, 기존 "복사하고 닫기" 다이얼로그에 공유 버튼
   병기).
2. **(중비용)** Kakao Link SDK 연동 — 커스텀 카드(버튼: "곁에 앱에서
   열기") 원하면. 우선순위는 가인님 판단.
3. **(고비용, 후순위)** 인스타그램 스토리 네이티브 공유. 사용 빈도 대비
   구현 비용이 커서, 실사용 데이터(다른 채널 공유 비율)를 보고 우선순위
   재확인 권장.
4. **(나중)** 동적 개인화 OG 이미지 — 별도 렌더링 인프라 필요.
