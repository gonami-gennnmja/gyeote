## 곁에(Gyeote) 팀 공통 규칙

이 프로젝트는 장거리 커플·친구·가족용 위치공유/사진/버킷리스트 공유 앱 "곁에"입니다.
스택: Flutter(프론트) + Supabase(백엔드, Postgres+PostGIS+Realtime).

### 팀 구성 (tmux 파인 번호)
- Pane 0: Plexa (Planner) — 계획 수립, 작업 배분
- Pane 1: Din (Designer) — UI/UX 설계
- Pane 2: Diana (Frontend Dev) — Flutter 클라이언트 구현
- Pane 3: Dexa (Backend Dev) — Supabase/API 구현
- Pane 4: Tom (QA/Tester) — 테스트 작성·실행
- Pane 5: Rena (Reviewer) — 코드 리뷰

### 팀원 호출 방법
tmux send-keys -t team:0.N "이름, 지시내용" Enter
(N은 위 번호. 예: Plexa가 Diana 부를 때 -t team:0.2)

### 작업 원칙
- 각자 담당 영역 밖의 파일은 함부로 수정하지 않는다.
- 작업 완료 후 Plexa(Pane 0)에게 tmux send-keys로 결과를 보고한다.
- 같은 기능을 여러 명이 동시에 중복 구현하지 않는다 — Plexa가 배분한 범위만 진행한다.

### tmux send-keys 사용 시 주의
팀원을 tmux send-keys로 호출할 때는 텍스트와 Enter를 반드시 분리해서 보낸다:
tmux send-keys -t team:0.N "메시지"
sleep 0.3
tmux send-keys -t team:0.N "" Enter
텍스트와 Enter를 한 번에 같이 보내면 메시지가 입력창에 앉은 채 전송되지 않는 문제가 자주 발생한다.

### tmux send-keys 사용 시 주의
팀원을 tmux send-keys로 호출할 때는 텍스트와 Enter를 반드시 분리해서 보낸다:
tmux send-keys -t team:0.N "메시지"
sleep 0.3
tmux send-keys -t team:0.N "" Enter
텍스트와 Enter를 한 번에 같이 보내면 메시지가 입력창에 앉은 채 전송되지 않는 문제가 자주 발생한다.

### 커밋 규칙 (필수)
모든 커밋은 /workspace/.github/COMMIT_CONVENTION.md 형식을 따른다.
- 제목에 [FE]/[BE]/[QA]/[Design]/[Docs]/[Chore] 태그
- 본문에 직전 커밋 이후 변경 파일을 분야별로 나열
- 사람이 직접 쓴 것처럼 자연스러운 톤, AI 생성 표시(Generated with Claude Code 등) 절대 넣지 않음
- git log -1 로 직전 커밋 확인 후 그 이후 git diff --name-only로 변경분 파악해서 분류
