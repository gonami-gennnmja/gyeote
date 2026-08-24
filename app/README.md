# 곁에(Gyeote) — Flutter 앱

Flutter/Dart 자체는 안다는 전제로, 이 저장소에서만 필요한 정보만 적는다.

## SDK 버전

`pubspec.yaml`의 `environment` 절(`sdk: '>=3.3.0 <4.0.0'`, `flutter: '>=3.19.0'`)이
버전 제약이다. 현재 이 컨테이너에서 검증된 조합은 **Flutter 3.47.1 (stable) /
Dart 3.13.1**(둘 다 위 제약을 만족)이다.

## SDK 설치 위치 / PATH

`/opt/flutter`에 `git clone`으로 설치(시스템 공용 경로, 특정 계정 세션에 종속되지
않음). PATH는 `/etc/profile.d/flutter.sh`와 `/etc/bash.bashrc` 양쪽에
`export PATH="/opt/flutter/bin:$PATH"`를 추가해뒀다 — 새로 여는 셸/pane은 바로
`flutter`/`dart`를 쓸 수 있고, 이미 열려 있던 셸은 새로 열거나
`source /etc/bash.bashrc`가 필요하다.

## 자주 쓰는 명령

`app/` 디렉터리에서:

```bash
flutter pub get   # 의존성 설치
flutter analyze   # 정적 분석
flutter test      # 단위 테스트
```

`flutter analyze`는 현재 info 레벨 6건이며(전부 deprecated API 사용 또는
스타일 권고, 예: `withOpacity`/`groupValue` deprecated, `prefer_const_constructors`)
**에러는 없다**. 이 6건은 기능과 무관해 별도 정리 작업으로 다음에 처리한다.

## 얕은 클론에서 버전 체크가 멈추는 문제

Flutter SDK를 `git clone --depth 1`(얕은 클론)으로 설치하면, 첫 `flutter`
명령 실행 시 내장 버전 체크가 `git fetch --tags`(깊이 제한 없음)를 시도하다가
멈출 수 있다 — 네트워크 자체는 정상이어도 얕은 클론에 전체 태그를 무제한으로
가져오려는 이 특정 fetch만 응답 없이 멈추는 현상이다. 겉보기엔 그냥 멈춘
것처럼 보여서 원인을 모르면 디버깅에 시간이 걸린다.

우회: 버전 체크 캐시 스탬프 파일을 미리 최신 시각으로 채워서 첫 실행이 네트워크
호출 없이 캐시를 쓰게 만든다(유효기간 3일, 이후 다시 겪으면 같은 방법을 반복하면
된다).

```bash
python3 -c "
import json, datetime
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
print(json.dumps({'lastTimeVersionWasChecked': now, 'lastKnownRemoteVersion': now}))
" > /opt/flutter/bin/cache/flutter_version_check.stamp
```
