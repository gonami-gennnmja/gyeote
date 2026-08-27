# 곁에(Gyeote) 커밋 컨벤션

## 태그
변경된 파일이 속한 분야에 따라 제목 앞에 태그를 붙인다. 한 커밋에 여러 분야가 섞이면 태그를 여러 개 나열한다.

- [FE] 프론트엔드 (Flutter, app/lib/**)
- [BE] 백엔드 (Supabase, supabase/**)
- [QA] 테스트 (test/**, supabase/tests/**)
- [Design] UI/UX 설계 문서 (docs/design/**)
- [Docs] 문서 (README, docs/** 중 설계 문서 제외)
- [Chore] 설정, 환경, CLAUDE.md, 훅 등

## 제목 톤
- 사람이 직접 커밋한 것처럼, 개발자가 평소 쓰는 반말/평서체로 쓴다.
- 예: "위치공유 mode='off' 체크 안 되던 버그 고침", "지도 화면 로딩 스피너 추가"
- 금지 표현: "Implemented comprehensive ~", "This commit adds ~", "종합적으로 구현함" 같은 AI스러운 격식체
- AI 생성 표시(Generated with Claude Code, Co-Authored-By: Claude 등) 절대 포함하지 않는다.

## 본문 형식
직전 커밋 이후 변경된 파일을 분야별로 묶어서 나열한다.
