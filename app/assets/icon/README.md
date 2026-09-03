# 앱 아이콘 원본 (v0.1 임시안)

Din 제작, 2026-09-03. 스펙·배경은 `docs/design/v0.1-release-assets.md` §1.

컨셉: 물방울형 위치 핀 + 하트 컷아웃. 배경 `#FF4081`(앱 테마 시드색), 심볼 흰색.
v0.2에서 정식 일러스트로 교체 예정(스토어 재심사 사유 아님).

## 파일

| 파일 | 용도 |
|---|---|
| `app_icon.png` (1024²) | `flutter_launcher_icons`의 `image_path`. iOS AppIcon + Android 레거시 정사각. 핑크 배경 포함(불투명) |
| `app_icon_foreground.png` (1024²) | adaptive 전경. 투명 배경, 심볼이 프레임을 크게 채움 — 생성기의 16% inset을 전제로 한 크기 |
| `app_icon_background.png` (1024²) | adaptive 배경. 단색 `#FF4081` (색 문자열 `"#FF4081"`로 대체 가능) |
| `app_icon_monochrome.png` (1024²) | Android 13+ 테마 아이콘용 흰 실루엣. `adaptive_icon_monochrome`로 배선 시 사용 |
| `store_icon_512.png` (512²) | Google Play 등재 아이콘 |
| `feature_graphic.png` (1024×500) | Google Play 피처 그래픽 |
| `*.svg` | 각 PNG의 벡터 원본. v0.2 교체 시 여기서 편집 후 재렌더 |

## 재생성

```
cd app && dart run flutter_launcher_icons
```

`android/app/src/main/res/mipmap-*` + `ios/Runner/Assets.xcassets/AppIcon.appiconset`가
생성된다. SVG를 고쳤으면 PNG부터 다시 뽑을 것(예: `rsvg-convert -w 1024 -h 1024 app_icon.svg -o app_icon.png`).
