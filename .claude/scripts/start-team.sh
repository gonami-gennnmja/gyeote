#!/bin/bash
cd /workspace

# 1. tmux 세션 없으면 생성
if ! tmux has-session -t team 2>/dev/null; then
    tmux new-session -d -s team -x 220 -y 50
    tmux split-window -t team:0.0 -h
    tmux split-window -t team:0.1 -h
    tmux split-window -t team:0.2 -h
    tmux split-window -t team:0.3 -h
    tmux split-window -t team:0.4 -h
    tmux select-layout -t team:0 even-horizontal
    tmux select-layout -t team:0 main-vertical
    tmux set-option -t team main-pane-width 100
    tmux set-option -t team pane-border-status top
    tmux set-option -t team pane-border-format " #{pane_title} "
    tmux set-option -t team allow-rename off
    tmux select-pane -t team:0.0 -T "Plexa (Planner)"
    tmux select-pane -t team:0.1 -T "Din (Designer)"
    tmux select-pane -t team:0.2 -T "Diana (Frontend Dev)"
    tmux select-pane -t team:0.3 -T "Dexa (Backend Dev)"
    tmux select-pane -t team:0.4 -T "Tom (QA/Tester)"
    tmux select-pane -t team:0.5 -T "Rena (Reviewer)"
    echo "tmux 세션 생성 완료"
fi

# 2. 각 파인에 Claude 실행
MODELS=("opus" "sonnet" "sonnet" "sonnet" "sonnet" "sonnet")
for pane in 0 1 2 3 4 5; do
    tmux send-keys -t "team:0.$pane" "cd /workspace && claude --model ${MODELS[$pane]} --dangerously-skip-permissions" Enter
    sleep 4
done

echo "6개 파인 Claude 실행 요청 완료. 15초 후 역할 부여 시작..."
sleep 15

# 3. 역할 부여
send_msg() {
    tmux send-keys -t "team:0.$1" "$2"
    sleep 0.5
    tmux send-keys -t "team:0.$1" "" Enter
    sleep 1
}

send_msg 0 "너는 Plexa야. 팀의 Planner(총괄 기획자)야. 직접 코드를 작성하지 않고, 요구사항을 분석해서 Din(1)/Diana(2)/Dexa(3)/Tom(4)/Rena(5)에게 작업을 배분하고 결과를 취합해서 나(사용자)에게 보고하는 역할이야. 팀원 호출은 tmux send-keys -t team:0.N 형식을 쓰는데, 반드시 텍스트와 Enter를 분리해서 보내. 곁에 앱은 위치공유(Phase 0~1) 구현 및 리뷰 중이었고, HIGH-1/HIGH-2 이슈(스푸핑+접근범위 우회)는 Dexa가 커밋 전 수정해야 해."
send_msg 1 "너는 Din이야. 팀의 Designer야. UI/UX 구조, 화면 흐름, 컴포넌트 설계를 담당해. 코드 구현은 직접 하지 않고 Diana(pane 2)에게 디자인 스펙을 전달해. 작업 완료 후 Plexa(pane 0)에게 보고해."
send_msg 2 "너는 Diana야. 팀의 Frontend Dev야. Flutter 클라이언트 코드를 담당해. 백엔드 API가 필요하면 Dexa(pane 3)에게 요청해. 작업 완료 후 Plexa(pane 0)에게 보고해."
send_msg 3 "너는 Dexa야. 팀의 Backend Dev야. Supabase(DB 스키마, RLS, API, 실시간 브로드캐스트)를 담당해. 프론트엔드 코드는 건드리지 않아. HIGH-1/HIGH-2 이슈(스푸핑+접근범위 우회) 수정이 최우선이야. 작업 완료 후 Plexa(pane 0)에게 보고해."
send_msg 4 "너는 Tom이야. 팀의 QA/Tester야. Diana/Dexa가 구현한 기능이 요구사항대로 동작하는지 테스트를 작성·실행해. 기능 코드는 직접 수정하지 않아. 결과는 Plexa(pane 0)에게 보고해."
send_msg 5 "너는 Rena야. 팀의 Reviewer야. 변경된 코드의 버그/보안/성능/가독성을 검토해. 직접 코드를 고치지 않고 이슈만 보고해. Tom의 테스트가 끝난 후에 검토하고, 결과는 Plexa(pane 0)에게 보고해."

echo "역할 부여 완료. Remote Control 활성화 중..."
sleep 3
send_msg 0 "/remote-control Plexa-팀장"

echo "완료! tmux attach -t team 으로 확인하세요."
