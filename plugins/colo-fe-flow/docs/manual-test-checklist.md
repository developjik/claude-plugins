# Manual Test Checklist

`colo-fe-flow`를 실제로 손으로 돌려보면서 스캐폴드가 설계대로 이어지는지 확인하기 위한 체크리스트입니다.

이 문서는 자동 테스트가 아니라 사람 기준의 end-to-end 점검 순서를 제공합니다.

## 목적

이 체크리스트는 아래를 확인하기 위해 존재합니다.

- 로컬 runtime state가 실제 시나리오에서 일관되게 갱신되는지
- `route-workflow`가 다음 단계를 올바르게 계산하는지
- bootstrap, planning chain, execution loop가 실제 artifact와 함께 이어지는지
- utility skill과 hook이 실제 로그와 guardrail을 남기는지

## 권장 테스트 환경

- Git 저장소 하나를 별도로 준비
- `plugins/colo-fe-flow/`가 현재 워크스페이스에 존재
- `.mcp.json`에 최소 `atlassian`, `figma` 선언 존재
- 기존 `.colo-fe-flow/`가 없다면 더 좋음

권장 테스트 ticket:

- `FE-123`
- 요약 예시: `Checkout 페이지 개선`

## 사전 확인

1. `plugins/colo-fe-flow/scripts/lint-shell.sh`
기대 결과: `shell syntax check passed`

2. `plugins/colo-fe-flow/scripts/validate.sh`
기대 결과: 모든 `hooks/__tests__/*.test.sh` 통과 후 `colo-fe-flow scaffold validation passed`

3. 테스트 저장소 루트에 `.mcp.json` 존재 확인
기대 결과: `atlassian`, `figma`가 선언되어 있음

## 시나리오 1. Session Start 와 Hook 초기화

목적:
- `session-start.sh`가 runtime layout과 session log를 초기화하는지 확인

절차:

1. 아래 payload로 `session-start.sh` 실행

```bash
printf '{"cwd":"%s"}' "$(pwd)" | bash plugins/colo-fe-flow/hooks/session-start.sh
```

2. 아래 파일 확인

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.log/session.log`

기대 결과:

- `index.json`이 생성됨
- `session.log`에 `SESSION_START`가 기록됨
- 필수 MCP 선언이 없으면 hard fail이 아니라 session log에만 남고 종료됨

## 시나리오 2. Ticket Bootstrap

목적:
- active ticket 설정, ticket state 생성, `intake.md` 생성 확인

현재 권장 방식:
- 실제 `start-jira-ticket` MCP 흐름 대신 bootstrap helper로 먼저 검증

절차:

1. bootstrap helper 실행

```bash
source plugins/colo-fe-flow/hooks/lib/bootstrap.sh
cff_bootstrap_ticket "$(pwd)" "FE-123" "10001" "Checkout 페이지 개선" "https://jira.example.com/browse/FE-123"
```

2. 아래 파일 확인

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.state/tickets/FE-123.json`
- `docs/specs/FE-123/intake.md`

3. 아래 필드 확인

- `index.json.active_ticket == "FE-123"`
- `tickets/FE-123.json.phase == "branch-ready"`
- `tickets/FE-123.json.artifacts.intake.exists == true`
- `tickets/FE-123.json.sources.jira.summary == "Checkout 페이지 개선"`

기대 결과:

- ticket state가 생성됨
- `intake.md`가 생성됨
- 다음 라우팅 결과가 `clarify|missing_clarify`

## 시나리오 3. route-workflow 판정 확인

목적:
- 현재 상태에 맞게 다음 skill이 계산되는지 확인

절차:

1. route helper 실행

```bash
source plugins/colo-fe-flow/hooks/lib/routing.sh
cff_routing_route_result_json "$(pwd)" "이제 구현 들어가자"
```

2. bootstrap 직후 결과 확인

기대 결과:

- `decision == "redirect"` 또는 현재 단계에 맞는 판정
- `next_skill == "clarify"`
- `reason_code == "missing_clarify"`

3. utility 요청도 확인

```bash
cff_routing_route_result_json "$(pwd)" "티켓 목록 보여줘"
```

기대 결과:

- `decision == "execute"`
- `next_skill == "list-tickets"`

## 시나리오 4. Planning Chain

목적:
- `clarify -> plan -> design -> tasks.json` 흐름과 approval gate 확인

절차:

1. clarify draft 생성

```bash
source plugins/colo-fe-flow/hooks/lib/planning.sh
cff_planning_write_clarify "$(pwd)" "FE-123" "Checkout 요구사항을 정리하고 open question을 추출한다."
```

확인:

- `docs/specs/FE-123/clarify.md` 생성
- `phase == "clarify-draft"`
- `approvals.clarify.approved == false`

2. clarify 승인

```bash
cff_planning_approve_stage "$(pwd)" "FE-123" "clarify"
```

확인:

- `phase == "clarify-approved"`
- 다음 라우팅 결과가 `plan|missing_plan`

3. plan draft 생성 및 승인

```bash
cff_planning_write_plan "$(pwd)" "FE-123" "Checkout 변경 범위와 검증 순서를 계획한다."
cff_planning_approve_stage "$(pwd)" "FE-123" "plan"
```

확인:

- `plan.md` 생성
- `phase == "plan-approved"`
- 다음 라우팅 결과가 `design|missing_design`

4. design draft 생성 및 승인

```bash
cff_planning_write_design "$(pwd)" "FE-123" "Checkout UI/상태 변경 설계를 작성하고 atomic task를 생성한다."
cff_planning_approve_stage "$(pwd)" "FE-123" "design"
```

확인:

- `design.md` 생성
- `tasks.json` 생성
- `phase == "design-approved"`
- 다음 라우팅 결과가 `implement|ready_to_run_implement`

## 시나리오 5. Execution Loop

목적:
- `implement -> check -> iterate -> sync-docs -> complete-ticket` 전이 확인

절차:

1. implement 시작

```bash
source plugins/colo-fe-flow/hooks/lib/execution.sh
cff_execution_start_implementation "$(pwd)" "FE-123" "1" "0"
```

확인:

- `phase == "implementing"`
- `implementation.started == true`

2. implement 완료

```bash
cff_execution_finish_implementation "$(pwd)" "FE-123" "1" "1"
```

확인:

- 다음 라우팅 결과가 `check|missing_check`

3. 실패한 check 기록

```bash
cff_execution_write_check "$(pwd)" "FE-123" "failed" "2" "84" "테스트 실패와 gap 2건 발견"
```

확인:

- `check.md` 생성
- `phase == "checking"`
- `verification.last_check_status == "failed"`
- 다음 라우팅 결과가 `iterate|check_failed`

4. iterate 실행

```bash
cff_execution_iterate "$(pwd)" "FE-123" "Fix failed check gaps"
```

확인:

- `phase == "iterating"`
- `iteration.count == 1`
- `implementation.finished == false`

5. 성공한 check 기록

```bash
cff_execution_finish_implementation "$(pwd)" "FE-123" "1" "1"
cff_execution_write_check "$(pwd)" "FE-123" "passed" "0" "97" "테스트 통과, gap 없음"
```

확인:

- 다음 라우팅 결과가 `sync-docs|docs_not_synced`

6. sync-docs 실행

```bash
cff_execution_sync_docs "$(pwd)" "FE-123" '["docs/checkout.md"]' "변경 사항과 문서 반영을 마감한다."
```

확인:

- `wrapup.md` 생성
- `doc_sync.completed == true`
- `phase == "syncing-docs"`
- 다음 라우팅 결과가 `complete-ticket|ready_to_complete`

7. complete-ticket 실행

```bash
cff_execution_complete_ticket "$(pwd)" "FE-123"
```

확인:

- `status == "done"`
- `phase == "done"`

## 시나리오 6. Utility Skills

목적:
- 멀티 ticket 환경에서 목록 조회, 상태 조회, 전환이 되는지 확인

절차:

1. 두 번째 ticket 생성

```bash
cff_bootstrap_ticket "$(pwd)" "FE-456" "10002" "Header 정리" "https://jira.example.com/browse/FE-456"
```

2. ticket 목록 확인

```bash
source plugins/colo-fe-flow/hooks/lib/utility.sh
cff_utility_list_tickets_json "$(pwd)"
```

기대 결과:

- `active_ticket`
- `last_ticket`
- `tickets[].ticket_key`
- `tickets[].status`
- `tickets[].phase`

3. active ticket 상태 확인

```bash
cff_utility_show_ticket_status_json "$(pwd)"
```

기대 결과:

- active ticket 상태가 JSON으로 요약됨

4. ticket 전환

```bash
cff_utility_switch_ticket "$(pwd)" "FE-456"
```

확인:

- `index.json.active_ticket == "FE-456"`
- `index.json.last_ticket`이 이전 값으로 남음

## 시나리오 7. Hook 동작 확인

목적:
- session/tool/agent hook이 실제 guardrail과 logging을 수행하는지 확인

절차:

1. planning artifact 편집 전 pre-tool 실행

```bash
pre_payload=$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"docs/specs/FE-123/plan.md"}}' "$(pwd)")
echo "$pre_payload" | bash plugins/colo-fe-flow/hooks/pre-tool.sh
```

확인:

- `approvals.plan.approved == false`
- `approvals.design.approved == false`
- `phase == "plan-draft"`

2. 같은 payload로 post-tool 실행

```bash
echo "$pre_payload" | bash plugins/colo-fe-flow/hooks/post-tool.sh
```

확인:

- `artifacts.plan.exists == true`
- `.colo-fe-flow/.log/FE-123/orchestration.log`에 `POST_TOOL` 기록

3. agent lifecycle 확인

```bash
agent_payload=$(printf '{"cwd":"%s","agent_name":"planning-agent"}' "$(pwd)")
echo "$agent_payload" | bash plugins/colo-fe-flow/hooks/on-agent-start.sh
echo "$agent_payload" | bash plugins/colo-fe-flow/hooks/on-agent-stop.sh
```

확인:

- `.colo-fe-flow/.log/agents.log`에 `AGENT_START`, `AGENT_STOP` 기록

## 최종 합격 기준

아래가 모두 만족되면 현재 스캐폴드는 “실전 수동 테스트 기준 통과”로 볼 수 있습니다.

- session start가 runtime state와 session log를 만든다
- bootstrap 후 `clarify`로 이동할 수 있다
- planning chain 후 `tasks.json`이 생성된다
- execution loop 한 바퀴를 돌고 `done`까지 전이된다
- utility skill helper가 목록/상태/전환을 처리한다
- hook이 stale reset과 lifecycle log를 남긴다

## 현재 한계

이 체크리스트는 현재 스캐폴드 기준입니다. 아직 아래는 refinement 대상입니다.

- 실제 Jira/Confluence/Figma MCP를 각 skill 본문에 깊게 연결하는 작업
- `route-workflow`의 다음 skill 자동 실행을 실제 end-to-end skill invocation으로 묶는 작업
- hook policy를 더 강하게 만들거나 richer stale propagation을 넣는 작업
- agent를 실제 자동 orchestration으로 호출하는 상위 runner 연결
